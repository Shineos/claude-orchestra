#!/bin/bash
# dashboard.sh - 対話型Rich CLIダッシュボード（Pure Bash実装）
# 依存関係: jq, tput のみ（標準的なUnixコマンド）
# 
# これ1つでタスク管理のすべての操作が可能:
# - タスクの追加・開始・完了・削除
# - ログの表示
# - リアルタイム自動更新

set -euo pipefail

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/.claude"
TASKS_FILE="$CLAUDE_DIR/tasks.json"
ORCHESTRATOR="$SCRIPT_DIR/orchestrator.sh"

# TUIライブラリの読み込み
source "$SCRIPT_DIR/tui-core.sh"
source "$SCRIPT_DIR/tui-keyboard.sh"
source "$SCRIPT_DIR/tui-dialogs.sh"
source "$SCRIPT_DIR/tui-renderer.sh"

# Unicode罫線文字
BOX_TL="┌"
BOX_TR="┐"
BOX_BL="└"
BOX_BR="┘"
BOX_H="─"
BOX_V="│"
BOX_TL_BOLD="┏"
BOX_TR_BOLD="┓"
BOX_BL_BOLD="┗"
BOX_BR_BOLD="┛"
BOX_H_BOLD="━"
BOX_V_BOLD="┃"
PROGRESS_FULL="█"
PROGRESS_EMPTY="░"

# ANSI色定義（256色パレット）
COLOR_PENDING='\033[38;5;244m'      # Gray
COLOR_IN_PROGRESS='\033[38;5;226m'  # Yellow
COLOR_DONE='\033[38;5;82m'          # Green
COLOR_FAILED='\033[38;5;203m'       # Red
COLOR_PRIMARY='\033[38;5;33m'       # Blue
COLOR_SUCCESS='\033[38;5;82m'       # Green
COLOR_WARNING='\033[38;5;214m'      # Orange
COLOR_ERROR='\033[38;5;203m'        # Red
COLOR_DIM='\033[38;5;244m'          # Dim text
NC='\033[0m'                        # No Color
BOLD='\033[1m'

# グローバル変数
AUTO_REFRESH=false
LAST_REFRESH=0
MESSAGE=""
MESSAGE_COLOR=""

# ターミナル幅を取得（最小幅を保証）
get_terminal_width() {
    local width=$(tput cols)
    # 最小幅を50に設定
    if [[ $width -lt 50 ]]; then
        width=50
    fi
    echo "$width"
}

# ターミナル高さを取得
get_terminal_height() {
    tput lines
}

# ターミナル設定
setup_terminal() {
    # rawモードに設定（エコーなし、バッファリングなし）
    stty -echo -icanon time 0 min 0
    # カーソルを非表示
    tput civis
}

# ターミナルをクリーンアップ
cleanup_terminal() {
    # ターミナルを元に戻す
    stty sane
    # カーソルを表示
    tput cnorm
    # 画面クリア
    clear
}

# 文字列の表示幅を取得（ANSIエスケープシーケンス除去＋全角判定）
get_display_width() {
    local str="$1"
    # ANSIエスケープシーケンスを除去
    local clean_str=$(echo -e "$str" | sed "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    
    if [[ -z "$clean_str" ]]; then
        echo "0"
        return
    fi
    
    # 基本文字数
    local len=${#clean_str}
    
    # バイト数から全角文字（3バイト）の寄与分を計算
    local bytes=$(echo -n "$clean_str" | wc -c)
    local wide_chars=$(( (bytes - len) / 2 ))
    
    # 特殊対応: 罫線やブロック文字は3バイトだが幅1として扱う
    # Bashのパラメータ展開で対象文字以外を削除してカウント
    local blocks="${clean_str//[^█░┏┓┗┛━┃┌┐└┘─│]/}"
    local block_count=${#blocks}
    
    # 表示幅 = 基本文字数 + 全角寄与分 - ブロック文字調整
    local result=$(( len + wide_chars - block_count ))
    if [[ $result -lt 0 ]]; then result=0; fi
    echo "$result"
}

# 指定幅に切り詰める（末尾に...を付与）
truncate_string() {
    local str="$1"
    local max_width="$2"
    local current_width=$(get_display_width "$str")
    
    if [[ $current_width -le $max_width ]]; then
        echo "$str"
        return
    fi
    
    # 簡易的に切り詰め（バイナリサーチや1文字ずつの確認は遅いため）
    # 目標幅に近い文字数でカットしてから微調整
    local target_len=$((max_width - 3))
    if [[ $target_len -lt 1 ]]; then target_len=1; fi
    
    local truncated="${str:0:$target_len}"
    local width=$(get_display_width "$truncated")
    
    # 幅が足りなければ少しずつ足す、多ければ減らす
    while [[ $width -lt $target_len ]] && [[ ${#truncated} -lt ${#str} ]]; do
        truncated="${str:0:$((${#truncated}+1))}"
        width=$(get_display_width "$truncated")
    done
    
    while [[ $width -gt $target_len ]]; do
        truncated="${truncated:0:$((${#truncated}-1))}"
        width=$(get_display_width "$truncated")
    done
    
    echo "${truncated}..."
}

# スペースを指定数生成
repeat_space() {
    local count="$1"
    if [[ $count -gt 0 ]]; then
        printf "%${count}s" ""
    fi
}

# ヘッダー描画
draw_header() {
    local width=$(get_terminal_width)
    local inner_width=$((width - 4))
    
    # タスク統計を取得
    local total=$(jq '.tasks | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    local done=$(jq '[.tasks[] | select(.status == "completed")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    local percent=0
    
    if [[ $total -gt 0 ]]; then
        percent=$((done * 100 / total))
    fi
    
    # プログレスバーを生成（ターミナル幅に応じて調整）
    local bar_width=20
    if [[ $width -lt 80 ]]; then
        bar_width=10  # 狭い画面では短いバーを使用
    fi
    
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    local bar=""
    
    for ((i=0; i<filled; i++)); do
        bar+="$PROGRESS_FULL"
    done
    for ((i=0; i<empty; i++)); do
        bar+="$PROGRESS_EMPTY"
    done
    
    # ヘッダーボックスを描画 TOP
    printf "%b" "${COLOR_PRIMARY}${BOX_TL_BOLD}"
    # printf "%${inner_width}s" | tr ' ' "$BOX_H_BOLD" # tr置換だとマルチバイトでずれる可能性があるが、BOX_H_BOLDは1文字幅ならOK。
    # ここは単純にループで描画した方が安全
    for ((i=0; i<inner_width; i++)); do printf "%b" "$BOX_H_BOLD"; done
    printf "%b\n" "${BOX_TR_BOLD}${NC}"
    
    # タイトル行
    local title=" 🎯 Claude Orchestra"
    if [[ $width -ge 80 ]]; then
        title=" 🎯 Claude Orchestra - Task Dashboard"
    fi
    
    # 自動更新状態を表示
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        title+=" [自動更新]"
    fi
    
    local title_width=$(get_display_width "$title")
    local padding=$((inner_width - title_width))
    if [[ $padding -lt 0 ]]; then padding=0; fi
    
    printf "%b" "${COLOR_PRIMARY}${BOX_V_BOLD}${BOLD}${title}${NC}"
    repeat_space $padding
    printf "%b\n" "${COLOR_PRIMARY}${BOX_V_BOLD}${NC}"
    
    # プログレスバー行
    local progress_text=" Progress: ${bar} ${percent}% (${done}/${total} tasks)"
    # プログレスバーの文字幅計算（ANSIコード除去済みテキストで計算）
    # bar変数はUnicode文字を含むので注意
    local progress_text_plain=" Progress: ${bar} ${percent}% (${done}/${total} tasks)"
    local progress_width=$(get_display_width "$progress_text_plain")
    local progress_padding=$((inner_width - progress_width))
    if [[ $progress_padding -lt 0 ]]; then progress_padding=0; fi
    
    printf "%b" "${COLOR_PRIMARY}${BOX_V_BOLD}${NC}${progress_text}"
    repeat_space $progress_padding
    printf "%b\n" "${COLOR_PRIMARY}${BOX_V_BOLD}${NC}"
    
    # ボトムボーダー
    printf "%b" "${COLOR_PRIMARY}${BOX_BL_BOLD}"
    for ((i=0; i<inner_width; i++)); do printf "%b" "$BOX_H_BOLD"; done
    printf "%b\n" "${BOX_BR_BOLD}${NC}"
}

# タスクセクション描画
draw_task_section() {
    local status="$1"
    local title="$2"
    local color="$3"
    
    local width=$(get_terminal_width)
    local inner_width=$((width - 4))
    
    # タスク数を取得
    local count=$(jq "[.tasks[] | select(.status == \"$status\")] | length" "$TASKS_FILE" 2>/dev/null || echo "0")
    
    # セクションタイトル
    local title_text=" ${title} (${count}) "
    local title_width=$(get_display_width "$title_text")
    local left_padding=$(( (inner_width - title_width) / 2 ))
    local right_padding=$(( inner_width - title_width - left_padding ))
    
    echo ""
    printf "%b" "${BOX_TL}"
    for ((i=0; i<left_padding; i++)); do printf "%b" "$BOX_H"; done
    printf "%s" "$title_text"
    for ((i=0; i<right_padding; i++)); do printf "%b" "$BOX_H"; done
    printf "%b\n" "${BOX_TR}"
    
    # タスク一覧を取得
    local tasks
    tasks=$(jq -r ".tasks[] | select(.status == \"$status\") | \"#\(.id) │ \(.description)\"" "$TASKS_FILE" 2>/dev/null || echo "")
    
    if [[ -z "$tasks" || "$count" -eq 0 ]]; then
        # タスクがない場合
        local empty_text="(No tasks)"
        local empty_width=$(get_display_width "$empty_text")
        local empty_padding=$((inner_width - empty_width))
        printf "%b" "${BOX_V} ${COLOR_DIM}${empty_text}${NC}"
        repeat_space $((empty_padding - 1)) # 先頭のスペース分引く
        printf "%b\n" "${BOX_V}"
    else
        # タスクを表示
        while IFS= read -r line; do
            local max_task_width=$((inner_width - 2))
            
            # 切り詰め処理（自作関数使用）
            local truncated_line=$(truncate_string "$line" $max_task_width)
            local line_width=$(get_display_width "$truncated_line")
            local line_padding=$((inner_width - line_width - 1)) # 先頭スペース分
            if [[ $line_padding -lt 0 ]]; then line_padding=0; fi
            
            printf "%b" "${BOX_V} ${color}${truncated_line}${NC}"
            repeat_space $line_padding
            printf "%b\n" "${BOX_V}"
        done <<< "$tasks"
    fi
    
    # ボトムボーダー
    printf "%b" "${BOX_BL}"
    for ((i=0; i<inner_width; i++)); do printf "%b" "$BOX_H"; done
    printf "%b\n" "${BOX_BR}"
}

# フッター描画
draw_footer() {
    local width=$(get_terminal_width)
    local height=$(get_terminal_height)
    local border_width=$((width - 2))
    
    # フッター位置（画面下から4行目）
    tput cup $((height - 4)) 0
    
    # コマンドヘルプ
    printf "%b" "${COLOR_PRIMARY}"
    for ((i=0; i<border_width; i++)); do printf "%b" "$BOX_H_BOLD"; done
    printf "%b\n" "${NC}"
    
    tput cup $((height - 3)) 0
    printf "%b" "${COLOR_DIM}Commands: ${NC}"
    printf "%b" "${BOLD}[a]${NC}dd "
    printf "%b" "${BOLD}[s]${NC}tart "
    printf "%b" "${BOLD}[c]${NC}omplete "
    printf "%b" "${BOLD}[l]${NC}ogs "
    printf "%b" "${BOLD}[v]${NC}iew "
    printf "%b" "${BOLD}[d]${NC}elete "
    printf "%b" "${BOLD}[e]${NC}dit "
    printf "%b" "${BOLD}[w]${NC}atch "
    printf "%b" "${BOLD}[r]${NC}efresh "
    printf "%b" "${BOLD}[q]${NC}uit\n"
    
    tput cup $((height - 2)) 0
    printf "%b" "${COLOR_PRIMARY}"
    for ((i=0; i<border_width; i++)); do printf "%b" "$BOX_H_BOLD"; done
    printf "%b" "${NC}"
    
    # 一番下の行はプロンプトまたはメッセージ用に空ける
    tput cup $((height - 1)) 0
    tput el
}

# メッセージ表示
show_message() {
    local message="$1"
    local color="${2:-$COLOR_SUCCESS}"
    
    MESSAGE="$message"
    MESSAGE_COLOR="$color"
}

# メッセージ描画（古いバージョン、現在はshow_message()を使用）
draw_message() {
    if [[ -n "$MESSAGE" ]]; then
        local height=$(get_terminal_height)
        tput cup $((height - 1)) 0
        tput el
        printf "%b" "${MESSAGE_COLOR}${MESSAGE}${NC}"
    fi
}

# メッセージ表示
show_message() {
    local msg="$1"
    local color="${2:-$COLOR_PRIMARY}"
    local height=$(get_terminal_height)
    
    tput cup $((height - 1)) 0
    tput el
    printf "%b" "${color}${msg}${NC}"
    # メッセージ自体の表示は短時間なのでdraw_dashboardは呼ばない
}

# 画面全体を描画
draw_dashboard() {
    clear
    draw_header
    draw_task_section "pending" "PENDING" "$COLOR_PENDING"
    draw_task_section "in_progress" "IN PROGRESS" "$COLOR_IN_PROGRESS"
    draw_task_section "completed" "DONE" "$COLOR_DONE"
    draw_footer
    draw_message
}

# キー入力を読み取る（非ブロッキング）
read_key() {
    local key=""
    # 0.1秒待機して1文字読む。何もなければ空を返す
    IFS= read -rsn1 -t 0.1 key 2>/dev/null
    
    # キーが入力された場合、バッファに残っている入力を完全にフラッシュ
    if [[ -n "$key" ]]; then
        local dummy
        while read -rsn1 -t 0.001 dummy 2>/dev/null; do :; done
    fi
    echo "$key"
}

# 入力プロンプト
prompt_input() {
    local prompt="$1"
    prompt_edit_bottom "$prompt" ""
}

# 編集用プロンプト（デフォルト値あり、画面下部）
prompt_edit_bottom() {
    local prompt="$1"
    local default_value="$2"
    local height=$(get_terminal_height)
    local width=$(get_terminal_width)
    
    local input="$default_value"
    local cursor_pos=${#input}
    local input_area_width=$((width - ${#prompt} - 6))
    
    # カーソル表示
    printf "\033[?25h" >&2
    
    # 入力バッファをクリア
    if declare -f tui_flush_input >/dev/null; then
        tui_flush_input
    fi

    while true; do
        # 画面下部に描画
        printf "\033[%d;0H" "$((height - 1))" >&2
        printf "\033[2K" >&2
        printf "%b" "${BOLD}${COLOR_PRIMARY}❯ ${prompt}: ${NC}" >&2
        
        # 入力をボックス的に表示
        printf "${COLOR_PRIMARY}[${NC}${input}" >&2
        
        # 残りをスペースで埋める（簡易的）
        local remaining=$((input_area_width - ${#input}))
        if [[ $remaining -gt 0 ]]; then
            printf "%${remaining}s" "" >&2
        fi
        printf "${COLOR_PRIMARY}]${NC}" >&2
        
        # カーソル位置を合わせる
        local prompt_len=$(( ${#prompt} + 4 ))
        printf "\033[%d;%dH" "$((height - 1))" "$((prompt_len + cursor_pos + 1))" >&2
        
        local raw_key=$(tui_get_key)
        local key="${raw_key%_}"
        
        case "$key" in
            "$KEY_ENTER")
                echo "$input"
                return 0
                ;;
            "$KEY_ESCAPE")
                return 1
                ;;
            "$KEY_BACKSPACE"|"$'\x7f'")
                if [[ $cursor_pos -gt 0 ]]; then
                    input="${input:0:$((cursor_pos - 1))}${input:$cursor_pos}"
                    ((cursor_pos--))
                fi
                ;;
            "TIMEOUT")
                continue
                ;;
            *)
                # 通常文字（簡易的なバリデーション）
                if [[ ${#key} -eq 1 ]] && [[ "$key" =~ [[:print:]] ]]; then
                    if [[ ${#input} -lt $input_area_width ]]; then
                        input="${input:0:$cursor_pos}${key}${input:$cursor_pos}"
                        ((cursor_pos++))
                    fi
                fi
                ;;
        esac
    done
}

# 全タスクIDを取得（スペース区切り）
get_all_task_ids() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo ""
        return
    fi
    jq -r '.tasks | sort_by(.id) | .[].id' "$TASKS_FILE" | xargs echo
}

# 水平選択プロンプト（エージェント選択用）
prompt_select_horizontal() {
    local prompt="$1"
    local options_str="$2"
    local selected_idx="${3:-0}"
    
    local options=($options_str)
    local count=${#options[@]}
    local height=$(get_terminal_height)
    
    # カーソル非表示
    printf "\033[?25l" >&2
    
    # 入力バッファをクリア
    if declare -f tui_flush_input >/dev/null; then
        tui_flush_input
    fi

    while true; do
        # 画面下部（prompt_inputと同じ位置）に描画
        # input area is height-1 based on prompt_input logic
        printf "\033[%d;0H" "$((height - 1))" >&2
        printf "\033[2K" >&2
        printf "%b" "${BOLD}${COLOR_PRIMARY}❯ ${prompt}: ${NC}" >&2
        
        for ((i=0; i<count; i++)); do
            if [[ $i -eq $selected_idx ]]; then
                # 選択中: 反転表示
                printf "%b" "${REVERSE} ${options[$i]} ${NC} " >&2
            else
                # 非選択: 薄い色
                printf "%b" "${COLOR_DIM} ${options[$i]} ${NC} " >&2
            fi
        done
        
        # キー入力待機
        local raw_key=$(tui_get_key)
        local key="${raw_key%_}"
        
        if [[ "$key" == "TIMEOUT" ]]; then
            continue
        fi
        
        if [[ "$key" == "EOF" ]]; then
            return 1
        fi

        
        case "$key" in
            "$KEY_LEFT"|"h")
                ((selected_idx--))
                # ループさせる
                if [[ $selected_idx -lt 0 ]]; then selected_idx=$((count - 1)); fi
                ;;
            "$KEY_RIGHT"|"l")
                ((selected_idx++))
                # ループさせる
                if [[ $selected_idx -ge $count ]]; then selected_idx=0; fi
                ;;
            "$KEY_ENTER")
                printf "%s" "${options[$selected_idx]}"
                # 完了後のクリーンアップ
                printf "\033[%d;0H" "$((height - 1))" >&2
                printf "\033[2K" >&2
                return 0
                ;;
            "$KEY_ESCAPE"|"q")
                # キャンセル
                printf "\033[%d;0H" "$((height - 1))" >&2
                printf "\033[2K" >&2
                return 1
                ;;
        esac
    done
}

# タスク追加
add_task_interactive() {
    # echo "[DEBUG] Starting add_task_interactive" >> /tmp/claude_dashboard_debug.log
    
    # echo "[DEBUG] Calling prompt_input..." >> /tmp/claude_dashboard_debug.log
    # set +e to prevent crash if comsub fails (though prompt_input returns 0)
    local task_desc
    if ! task_desc=$(prompt_input "タスク説明を入力"); then
        # echo "[ERROR] prompt_input failed with exit code $?" >> /tmp/claude_dashboard_debug.log
        draw_dashboard
        return 1
    fi
    
    # echo "[DEBUG] Got task_desc='$task_desc'" >> /tmp/claude_dashboard_debug.log
    
    if [[ -n "$task_desc" ]]; then
        # 画面サイズに応じたダイアログ幅の計算
        local width=$(get_terminal_width)
        local dialog_width=$((width - 10))
        if [[ $dialog_width -gt 60 ]]; then dialog_width=60; fi

        # エージェント選択
        local agents="Auto(AI) frontend backend tests docs planner architect coder reviewer tester"
        local agent=""
        
        # New: Use horizontal selection prompt
        if agent=$(prompt_select_horizontal "Select Agent" "$agents" 0); then
             # Success
             :
        else
             # Cancelled
             draw_dashboard
             return
        fi

        # Auto(AI) の場合は空文字にする（orchestratorで自動判定させるため）

        
        # 画面を一時的にクリアしてコマンド実行結果を見せる
        tui_clear
        echo "Adding task: $task_desc..."
        
        # Check command
        # echo "[DEBUG] Running orchestrator add" >> /tmp/claude_dashboard_debug.log
        
        local tmp_out="/tmp/claude_dash_cmd.log"
        local success=false

        if [[ "$agent" == "Auto(AI)" ]]; then
            show_message "🤖 AIがタスクを分析・分解中..." "$COLOR_MAGENTA"
            # Autoモード: エージェント指定なしで実行し、自動確認を有効化
            if ORCH_AUTO_CONFIRM=yes ORCH_AUTO_LAUNCH=no bash "$ORCHESTRATOR" add "$task_desc" > "$tmp_out" 2>&1; then
                success=true
                # echo "[DEBUG] Orchestrator success" >> /tmp/claude_dashboard_debug.log
            else
                # echo "[DEBUG] Orchestrator failed: $(cat $tmp_out)" >> /tmp/claude_dashboard_debug.log
                :
            fi
        else
            show_message "⏳ タスクを追加中 ($agent)..." "$COLOR_PRIMARY"
            # 通常モード: エージェント指定あり
            if ORCH_AUTO_LAUNCH=no bash "$ORCHESTRATOR" add "$task_desc" "$agent" > "$tmp_out" 2>&1; then
                success=true
                # echo "[DEBUG] Orchestrator success" >> /tmp/claude_dashboard_debug.log
            else
                # echo "[DEBUG] Orchestrator failed: $(cat $tmp_out)" >> /tmp/claude_dashboard_debug.log
                :
            fi
        fi

        if [[ "$success" == "true" ]]; then
            # メッセージを解析して適切なフィードバックを表示
            if grep -q "タスク分解プラン" "$tmp_out"; then
                show_message "✓ タスクを自動分解して追加しました" "$COLOR_SUCCESS"
            else
                show_message "✓ タスクを追加しました" "$COLOR_SUCCESS"
            fi
        else
            local err_msg=$(grep -E "(Error|失敗|invalid|jq):" "$tmp_out" | head -n1 | sed 's/.*Error: //;s/.*\(jq:.*\)/\1/')
            [[ -z "$err_msg" ]] && err_msg="追加に失敗しました"
            show_message "✗ $err_msg" "$COLOR_ERROR"
        fi
        sleep 2
        draw_dashboard
    else
        draw_dashboard
    fi
}


# タスク開始
start_task_interactive() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "開始対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        show_message "⏳ タスク #$task_id を開始中..." "$COLOR_PRIMARY"
        local tmp_out="/tmp/claude_dash_cmd.log"
        if bash "$ORCHESTRATOR" start "$task_id" > "$tmp_out" 2>&1; then
            show_message "✓ タスク #$task_id を開始しました" "$COLOR_SUCCESS"
        else
            local err_msg=$(grep -E "(Error|失敗|invalid|jq):" "$tmp_out" | head -n1)
            [[ -z "$err_msg" ]] && err_msg="開始に失敗しました"
            show_message "✗ $err_msg" "$COLOR_ERROR"
        fi
        sleep 2
        draw_dashboard
    else
        draw_dashboard
    fi
}

# タスク完了
complete_task_interactive() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "完了対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        show_message "⏳ タスク #$task_id を完了中..." "$COLOR_PRIMARY"
        if bash "$ORCHESTRATOR" complete "$task_id" >/dev/null 2>&1; then
            show_message "✓ タスク #$task_id を完了しました" "$COLOR_SUCCESS"
        else
            show_message "✗ タスク #$task_id の完了に失敗しました" "$COLOR_ERROR"
        fi
        sleep 1
        draw_dashboard
    else
        draw_dashboard
    fi
}

# タスク編集
edit_task_interactive() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "編集対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        # 現在のタスク情報を取得
        local current_desc=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == ($id | tonumber)) | .description' "$TASKS_FILE" 2>/dev/null || echo "")
        
        if [[ -z "$current_desc" ]]; then
            show_message "✗ タスク #$task_id が見つかりません" "$COLOR_ERROR"
            draw_dashboard
            return
        fi

        local new_desc
        if ! new_desc=$(prompt_edit_bottom "新しい説明" "$current_desc"); then
            draw_dashboard
            return
        fi
        
        if [[ -n "$new_desc" && "$new_desc" != "$current_desc" ]]; then
             show_message "⏳ タスク #$task_id を更新中..." "$COLOR_PRIMARY"
             
             # jqで直接編集 (本来はorchestrator経由が良いが、editコマンドがないため直接編集)
             # バックアップ作成
             cp "$TASKS_FILE" "${TASKS_FILE}.bak"
             
             if jq --arg id "$task_id" --arg desc "$new_desc" '(.tasks[] | select(.id == ($id | tonumber))).description = $desc' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"; then
                 show_message "✓ タスク #$task_id を更新しました" "$COLOR_SUCCESS"
             else
                 mv "${TASKS_FILE}.bak" "$TASKS_FILE"
                 show_message "✗ 更新に失敗しました" "$COLOR_ERROR"
             fi
        fi
        sleep 1
        draw_dashboard
    else
        draw_dashboard
    fi
}

# タスク削除
delete_task_interactive() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "削除対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        show_message "⏳ タスク #$task_id を削除中..." "$COLOR_PRIMARY"
        if bash "$ORCHESTRATOR" delete "$task_id" >/dev/null 2>&1; then
            show_message "✓ タスク #$task_id を削除しました" "$COLOR_SUCCESS"
        else
            show_message "✗ タスク #$task_id の削除に失敗しました" "$COLOR_ERROR"
        fi
        sleep 1
        draw_dashboard
    else
        draw_dashboard
    fi
}

# タスク詳細表示
show_task_detail() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "詳細表示対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        # tui_task_detail_dialog が利用可能か確認
        if declare -f tui_task_detail_dialog >/dev/null; then
            while true; do
                # 詳細ダイアログを表示
                local action
                # サブシェルで実行して結果を取得する形だと描画がおかしくなる可能性があるが、
                # ここでは tui_task_detail_dialog が標準出力に結果を出すように修正したので
                # コマンド置換で受け取る
                if ! action=$(tui_task_detail_dialog "$task_id"); then
                    break
                fi
                
                # アクション処理
                if [[ "$action" == "close" ]]; then
                    break
                elif [[ "$action" == "start" ]]; then
                    show_message "⏳ タスク #$task_id を開始中..." "$COLOR_PRIMARY"
                    local tmp_out="/tmp/claude_dash_cmd.log"
                    if bash "$ORCHESTRATOR" start "$task_id" > "$tmp_out" 2>&1; then
                        show_message "✓ タスク #$task_id を開始しました" "$COLOR_SUCCESS"
                    else
                        local err_msg=$(grep -E "(Error|失敗|invalid|jq):" "$tmp_out" | head -n1)
                        [[ -z "$err_msg" ]] && err_msg="開始に失敗しました"
                        show_message "✗ $err_msg" "$COLOR_ERROR"
                    fi
                    sleep 2
                    break
                    
                elif [[ "$action" == "complete" ]]; then
                    show_message "⏳ タスク #$task_id を完了中..." "$COLOR_PRIMARY"
                    if bash "$ORCHESTRATOR" complete "$task_id" >/dev/null 2>&1; then
                        show_message "✓ タスク #$task_id を完了しました" "$COLOR_SUCCESS"
                    else
                        show_message "✗ タスク #$task_id の完了に失敗しました" "$COLOR_ERROR"
                    fi
                    sleep 1
                    break
                    
                elif [[ "$action" == "reset" ]]; then
                     show_message "⏳ タスク #$task_id をリセット中..." "$COLOR_PRIMARY"
                     # jqで直接ステータス変更 (orchestratorにresetコマンドがない場合)
                     cp "$TASKS_FILE" "${TASKS_FILE}.bak"
                     if jq --arg id "$task_id" '(.tasks[] | select(.id == ($id | tonumber))).status = "pending"' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"; then
                         show_message "✓ タスク #$task_id をリセットしました" "$COLOR_SUCCESS"
                     else
                         mv "${TASKS_FILE}.bak" "$TASKS_FILE"
                         show_message "✗ リセットに失敗しました" "$COLOR_ERROR"
                     fi
                     sleep 1
                     break
                     
                elif [[ "$action" == fail:* ]]; then
                    local reason="${action#fail:}"
                    show_message "⏳ タスク #$task_id を失敗としてマーク中..." "$COLOR_PRIMARY"
                     # jqで直接ステータス変更 & ノート追加
                     cp "$TASKS_FILE" "${TASKS_FILE}.bak"
                     # 失敗ステータスと理由をノートに追加
                     local note_obj="{\"text\": \"Failed: $reason\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
                     
                     if jq --arg id "$task_id" --argjson note "$note_obj" '
                        (.tasks[] | select(.id == ($id | tonumber))) |= (.status = "failed" | .notes += [$note])
                     ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"; then
                         show_message "✓ タスク #$task_id を失敗としてマークしました" "$COLOR_SUCCESS"
                     else
                         mv "${TASKS_FILE}.bak" "$TASKS_FILE"
                         show_message "✗ 更新に失敗しました" "$COLOR_ERROR"
                     fi
                     sleep 1
                     break
                
                elif [[ "$action" == edit:* ]]; then
                    # edit:field:value
                    local content="${action#edit:}"
                    local field="${content%%:*}"
                    local value="${content#*:}"
                    
                    show_message "Updating $field..." "$COLOR_PRIMARY"
                    cp "$TASKS_FILE" "${TASKS_FILE}.bak"
                    
                    if jq --arg id "$task_id" --arg field "$field" --arg val "$value" '
                        (.tasks[] | select(.id == ($id | tonumber)))[$field] = $val
                    ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"; then
                         show_message "✓ $field 更新完了" "$COLOR_SUCCESS"
                    else
                         mv "${TASKS_FILE}.bak" "$TASKS_FILE"
                         show_message "✗ 更新に失敗しました" "$COLOR_ERROR"
                    fi
                    # 編集後はループ継続して詳細を表示し続ける（再描画される）
                    sleep 0.5
                    
                elif [[ "$action" == add-note:* ]]; then
                    local note_text="${action#add-note:}"
                    if [[ -n "$note_text" ]]; then
                        local note_obj="{\"text\": \"$note_text\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
                        cp "$TASKS_FILE" "${TASKS_FILE}.bak"
                        if jq --arg id "$task_id" --argjson note "$note_obj" '
                            (.tasks[] | select(.id == ($id | tonumber))).notes += [$note]
                        ' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"; then
                             show_message "✓ ノートを追加しました" "$COLOR_SUCCESS"
                        else
                             mv "${TASKS_FILE}.bak" "$TASKS_FILE"
                             show_message "✗ 追加に失敗しました" "$COLOR_ERROR"
                        fi
                    fi
                    sleep 0.5
                fi
            done
            draw_dashboard
        else
            show_message "詳細表示機能はサポートされていません" "$COLOR_WARNING"
            sleep 1
            draw_dashboard
        fi
    else
        draw_dashboard
    fi
}

# ログ表示
show_logs_interactive() {
    local ids=$(get_all_task_ids)
    if [[ -z "$ids" ]]; then
        show_message "✗ タスクが見つかりません" "$COLOR_ERROR"
        draw_dashboard
        return
    fi
    
    local task_id
    if ! task_id=$(prompt_select_horizontal "ログ表示対象" "$ids"); then
        draw_dashboard
        return
    fi
    
    if [[ -n "$task_id" ]]; then
        local log_file="$CLAUDE_DIR/tasks/$task_id/logs/agent.log"
        
        if [[ -f "$log_file" ]]; then
            # ターミナルを元に戻してlessで表示
            cleanup_terminal
            less "$log_file"
            setup_terminal
            draw_dashboard
        else
            show_message "✗ ログが見つかりません: タスク #$task_id" "$COLOR_ERROR"
            draw_dashboard
        fi
    else
        draw_dashboard
    fi
}

# 自動更新トグル
toggle_auto_refresh() {
    if [[ "$AUTO_REFRESH" == "true" ]]; then
        AUTO_REFRESH=false
        show_message "自動更新: OFF" "$COLOR_WARNING"
    else
        AUTO_REFRESH=true
        show_message "自動更新: ON (5秒ごと)" "$COLOR_SUCCESS"
    fi
    draw_dashboard
}

# メインループ
main_loop() {
    LAST_REFRESH=$(date +%s)
    
    while true; do
        # 自動更新チェック
        if [[ "$AUTO_REFRESH" == "true" ]]; then
            local now=$(date +%s)
            if [[ $((now - LAST_REFRESH)) -ge 5 ]]; then
                draw_dashboard
                LAST_REFRESH=$now
            fi
        fi
        
        # キー入力を読み取る
        local key=$(read_key)
        
        case "$key" in
            a) add_task_interactive || true ;;
            s) start_task_interactive || true ;;
            c) complete_task_interactive || true ;;
            l) show_logs_interactive || true ;;
            d) delete_task_interactive || true ;;
            v) show_task_detail || true ;;
            e) edit_task_interactive || true ;;
            w) toggle_auto_refresh ;;
            r) draw_dashboard; LAST_REFRESH=$(date +%s) ;;
            q) break ;;
        esac
        
        sleep 0.1  # CPU使用率を抑える
    done
}

# メイン処理
main() {
    # プロジェクトルートに移動
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd "$script_dir/../.." || exit 1
    
    # 引数解析
    for arg in "$@"; do
        if [[ "$arg" == "--watch" ]]; then
            AUTO_REFRESH=true
        fi
    done

    # tasks.jsonの存在確認
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo "Error: tasks.json not found at $TASKS_FILE"
        exit 1
    fi
    
    # クリーンアップハンドラを設定
    trap cleanup_terminal EXIT INT TERM
    
    # ターミナル設定
    setup_terminal
    
    # 初回描画
    draw_dashboard
    
    # メインループ
    main_loop
    
    # クリーンアップ
    cleanup_terminal
}

# スクリプト実行
main "$@"
