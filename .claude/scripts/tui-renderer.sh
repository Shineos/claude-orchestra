#!/bin/bash
# TUI Renderer
#
# 画面描画エンジン

# このファイルはtui-core.shとtui-keyboard.shの後でsourceする必要がある

# =============================================================================
# 描画状態管理
# =============================================================================

# 画面キャッシュ（再描画最適化用）
declare -gA TUI_SCREEN_CACHE=()
declare -g TUI_SCREEN_DIRTY=true

# カーソル位置
declare -g TUI_CURSOR_ROW=0
declare -g TUI_CURSOR_COL=0
declare -g TUI_CURSOR_VISIBLE=false

# スクロール位置
declare -g TUI_SCROLL_ROW=0
declare -g TUI_SCROLL_COL=0

# フォーカス
declare -g TUI_FOCUSED_COLUMN=0  # 0-4 (pending, in_progress, review, completed, rejected)
declare -g TUI_SELECTED_TASK_ID=0

# =============================================================================
# 画面管理
# =============================================================================

# 画面をダーティ状態にする
tui_mark_dirty() {
    TUI_SCREEN_DIRTY=true
}

# 画面がダーティかどうか
tui_is_dirty() {
    [[ "$TUI_SCREEN_DIRTY" == "true" ]]
}

# 画面をクリーン状態にする
tui_mark_clean() {
    TUI_SCREEN_DIRTY=false
}

# 画面の再描画が必要かどうかをチェック
tui_needs_redraw() {
    tui_is_dirty
}

# =============================================================================
# セル描画
# =============================================================================

# 指定位置にテキストを描画（キャッシュ付き）
tui_draw_cell() {
    local row=$1
    local col=$2
    local text="$3"
    local color="${4:-$NC}"
    local attr="${5:-}"

    local cache_key="${row}:${col}:${text}"
    local cached="${TUI_SCREEN_CACHE[$cache_key]}"

    if [[ "$cached" == "${color}${attr}" ]]; then
        # 既に描画済み
        return 0
    fi

    tui_move "$row" "$col"
    printf "${color}${attr}${text}${NC}"
    TUI_SCREEN_CACHE[$cache_key]="${color}${attr}"
    TUI_SCREEN_DIRTY=false
}

# セルをクリア
tui_clear_cell() {
    local row=$1
    local col=$2
    local width=${3:-1}

    tui_move "$row" "$col"
    printf "%${width}s" " "
}

# 行をクリア
tui_clear_line() {
    local row=$1
    local start_col=${2:-0}

    tui_move "$row" "$start_col"
    tput el
}

# =============================================================================
# 選択カーソル描画
# =============================================================================

# 選択カーソルを描画
tui_draw_selection_cursor() {
    local row=$1
    local col=$2
    local width=$3
    local height=$4
    local color="${5:-$COLOR_PRIMARY}"

    # 反転表示で選択を表現
    tui_move "$row" "$col"
    printf "${REVERSE}"

    # カーソルの幅だけ描画
    local i=0
    while [[ $i -lt $width ]]; do
        printf " "
        ((i++))
    done

    printf "${NC}"
}

# 進捗バーを描画
tui_progress_bar() {
    local percentage=$1
    local width=${2:-30}
    local filled_char="${3:-█}"
    local empty_char="${4:-░}"
    local color="${5:-$COLOR_SUCCESS}"

    local filled=$(( width * percentage / 100 ))
    local empty=$(( width - filled ))

    printf "[${color}"
    tui_repeat "$filled" "$filled_char"
    printf "${NC}${COLOR_DIM}"
    tui_repeat "$empty" "$empty_char"
    printf "${NC}] %3d%%" "$percentage"
}

# =============================================================================
# タスクカード描画
# =============================================================================

# タスクカードを描画
tui_draw_task_card() {
    local row=$1
    local col=$2
    local width=$3
    local task_id="$4"
    local description="$5"
    local agent="$6"
    local priority="$7"
    local status="$8"
    local selected="${9:-false}"

    local height=5
    local color=$(tui_get_status_color "$status")
    local agent_color=$(tui_get_agent_color "$agent")
    local priority_color=$(tui_get_priority_color "$priority")
    local priority_badge=$(tui_get_priority_badge "$priority")

    # 選択状態の場合は反転
    if [[ "$selected" == "true" ]]; then
        printf "${REVERSE}"
    fi

    # 上辺
    tui_move "$row" "$col"
    printf "${color}┌${NC}"
    tui_hline $((width - 2)) " "
    printf "${color}┐${NC}"

    # タスクIDと優先度
    tui_move $((row + 1)) "$col"
    printf "${color}│${NC} "
    printf "${BOLD}#${task_id}${NC} "
    printf "${priority_badge} "
    local rest_width=$((width - 10 - ${#task_id}))
    printf "%${rest_width}s" " "
    printf "${color}│${NC}"

    # 説明
    local short_desc=$(tui_truncate "$description" $((width - 4)))
    tui_move $((row + 2)) "$col"
    printf "${color}│${NC} "
    printf "${color}${short_desc}${NC}"
    rest_width=$((width - 4 - ${#short_desc}))
    printf "%${rest_width}s" " "
    printf "${color}│${NC}"

    # エージェント
    local agent_cap="${agent^}"
    tui_move $((row + 3)) "$col"
    printf "${color}│${NC} "
    printf "${agent_color}${agent_cap}${NC} "
    rest_width=$((width - 6 - ${#agent_cap}))
    printf "%${rest_width}s" " "
    printf "${color}│${NC}"

    # 下辺
    tui_move $((row + 4)) "$col"
    printf "${color}└${NC}"
    tui_hline $((width - 2)) " "
    printf "${color}┘${NC}"

    # 反転解除
    if [[ "$selected" == "true" ]]; then
        printf "${NC}"
    fi
}

# コンパクトタスク表示（1行）
tui_draw_task_compact() {
    local row=$1
    local col=$2
    local width=$3
    local task_id="$4"
    local description="$5"
    local agent="$6"
    local priority="$7"
    local status="$8"
    local selected="${9:-false}"

    local color=$(tui_get_status_color "$status")
    local priority_badge=$(tui_get_priority_badge "$priority")

    # 選択状態
    if [[ "$selected" == "true" ]]; then
        printf "${REVERSE}${BOLD}"
    fi

    tui_move "$row" "$col"

    # タスクID
    printf "${color}#${task_id}${NC} "
    if [[ "$selected" == "true" ]]; then
        printf "${REVERSE}${BOLD}"
    fi

    # 優先度バッジ
    printf " ${priority_badge} "

    # 説明
    local max_desc=$((width - 12))
    local short_desc=$(tui_truncate "$description" "$max_desc")
    printf "${short_desc}"

    # 反転解除
    printf "${NC}"
}

# =============================================================================
# カラム描画
# =============================================================================

# カラムヘッダーを描画
tui_draw_column_header() {
    local row=$1
    local col=$2
    local width=$3
    local title="$4"
    local count=$5
    local focused="${6:-false}"

    if [[ "$focused" == "true" ]]; then
        printf "${BOLD}${COLOR_PRIMARY}"
    fi

    # タイトルとカウント
    local header_text="${title} (${count})"
    local header_len=${#header_text}
    local padding=$(( (width - header_len - 2) / 2 ))

    tui_move "$row" "$col"
    printf "┌"
    tui_hline $((width - 2)) "─"
    printf "┐"

    tui_move $((row + 1)) "$col"
    printf "│"
    printf "%${padding}s" " "
    printf "${header_text}"
    printf "%$((width - padding - header_len - 2))s" " "
    printf "│"

    tui_move $((row + 2)) "$col"
    printf "├"
    tui_hline $((width - 2)) "─"
    printf "┤"

    printf "${NC}"
}

# カラムを描画
tui_draw_column() {
    local row=$1
    local col=$2
    local width=$3
    local height=$4
    local status="$5"
    local tasks_json="$6"
    local selected_id="${7:-}"

    # タスクを配列として取得（空白を削除）
    local task_count=$(echo "$tasks_json" | jq 'length' 2>/dev/null | tr -d '[:space:]')
    task_count=${task_count:-0}

    # カラム描画
    local current_row=$row
    local task_idx=0
    local max_row=$((row + height))

    while [[ $current_row -lt $max_row ]]; do
        if [[ $task_idx -lt $task_count ]]; then
            local task=$(echo "$tasks_json" | jq ".[$task_idx]" 2>/dev/null)
            local task_id=$(echo "$task" | jq -r '.id' 2>/dev/null | tr -d '[:space:]')
            local description=$(echo "$task" | jq -r '.description' 2>/dev/null)
            local agent=$(echo "$task" | jq -r '.agent' 2>/dev/null)
            local priority=$(echo "$task" | jq -r '.priority' 2>/dev/null)

            local selected="false"
            [[ "$task_id" == "$selected_id" ]] && selected="true"

            # コンパクト描画（1行）
            tui_draw_task_compact "$current_row" $((col + 1)) $((width - 2)) \
                "$task_id" "$description" "$agent" "$priority" "$status" "$selected"

            ((task_idx++))
        else
            # 空行
            tui_move "$current_row" $((col + 1))
            printf "%$((width - 2))s" " "
        fi

        ((current_row++))
    done

    # 下辺
    tui_move "$current_row" "$col"
    printf "│"
    tui_hline $((width - 2)) " "
    printf "│"
    ((current_row++))

    tui_move "$current_row" "$col"
    printf "└"
    tui_hline $((width - 2)) "─"
    printf "┘"
}

# =============================================================================
# ヘッダー描画
# =============================================================================

# メインヘッダーを描画
tui_draw_header() {
    local cols=$(tui_get_cols | tr -d '[:space:]')
    cols=${cols:-80}

    tui_move 0 0

    # 上部ボックス
    printf "╔"
    tui_hline $((cols - 2)) "═"
    printf "╗"

    # タイトル行
    tui_move 1 0
    printf "║"
    printf "${BOLD}${COLOR_PRIMARY}  %-50s${NC}" "Claude Orchestra"
    printf "%$((cols - 60))s" " "
    printf "[Auto: 5s] [?]"
    printf "║"

    # 下部ボックス
    tui_move 2 0
    printf "╠"
    tui_hline $((cols - 2)) "═"
    printf "╣"
}

# サマリーセクションを描画
tui_draw_summary() {
    local row=$1
    local col=$2
    local width=$3

    local stats=$(tui_get_stats)
    local total=$(echo "$stats" | jq -r '.total' 2>/dev/null | tr -d '[:space:]')
    local completed=$(echo "$stats" | jq -r '.completed' 2>/dev/null | tr -d '[:space:]')
    local in_progress=$(echo "$stats" | jq -r '.in_progress' 2>/dev/null | tr -d '[:space:]')
    local failed=$(echo "$stats" | jq -r '.rejected' 2>/dev/null | tr -d '[:space:]')

    # デフォルト値設定
    total=${total:-0}
    completed=${completed:-0}
    in_progress=${in_progress:-0}
    failed=${failed:-0}

    # 完了率
    local completion_rate=0
    if [[ $total -gt 0 ]]; then
        completion_rate=$(( completed * 100 / total ))
    fi

    # ボックス描画
    tui_box "$row" "$col" $width 5 "📈 Summary" "$COLOR_BORDER"

    # 統計表示
    local stat_row=$((row + 2))
    tui_move "$stat_row" $((col + 2))
    printf "Tasks: ${BOLD}${COLOR_PRIMARY}%s${NC}  " "$total"
    printf "Done: ${BOLD}${COLOR_COMPLETED}%s${NC} (%d%%)  " "$completed" "$completion_rate"
    printf "Active: ${BOLD}${COLOR_IN_PROGRESS}%s${NC}  " "$in_progress"
    printf "Failed: ${BOLD}${COLOR_REJECTED}%s${NC}" "$failed"

    # 進捗バー
    tui_move $((stat_row + 1)) $((col + 2))
    tui_progress_bar "$completion_rate" $((width - 6))
}

# =============================================================================
# フッター描画
# =============================================================================

# キーヘルプフッターを描画
tui_draw_footer() {
    local rows=$(tui_get_rows | tr -d '[:space:]')
    rows=${rows:-24}
    local cols=$(tui_get_cols | tr -d '[:space:]')
    cols=${cols:-80}

    local row=$((rows - 2))

    tui_move "$row" 0

    # 区切り
    printf "╠"
    tui_hline $((cols - 2)) "═"
    printf "╣"

    # キーヘルプ
    tui_move $((row + 1)) 0
    printf "║"
    printf " ${COLOR_DIM}[↑↓:Move]${NC} "
    printf " ${COLOR_DIM}[Enter:Details]${NC} "
    printf " ${COLOR_DIM}[s:Start]${NC} "
    printf " ${COLOR_DIM}[c:Complete]${NC} "
    printf " ${COLOR_DIM}[f:Fail]${NC} "
    printf " ${COLOR_DIM}[q:Quit]${NC} "
    printf "%$((cols - 65))s" " "
    printf "║"

    # 下部ボックス
    tui_move $((row + 2)) 0
    printf "╚"
    tui_hline $((cols - 2)) "═"
    printf "╝"
}

# =============================================================================
# タスクボード描画（メイン）
# =============================================================================

# タスクボード全体を描画
tui_draw_taskboard() {
    local rows=$(tui_get_rows | tr -d '[:space:]')
    rows=${rows:-24}
    local cols=$(tui_get_cols | tr -d '[:space:]')
    cols=${cols:-80}

    # レイアウト計算
    local header_height=3
    local summary_height=6
    local footer_height=3
    local board_row=$((header_height + summary_height))
    local board_height=$((rows - header_height - summary_height - footer_height))
    local col_width=14
    local col_count=5
    local board_width=$((col_width * col_count + 6))
    local board_col=$(( (cols - board_width) / 2 ))

    # 画面をクリア
    tui_clear

    # ヘッダー
    tui_draw_header

    # サマリー
    tui_draw_summary 3 $((board_col - 2)) $((board_width + 4))

    # カラム定義
    local columns=("pending" "in_progress" "review_needed" "completed" "rejected")
    local titles=("Pending" "In Prog" "Review" "Done" "Reject")
    local column_colors=("$COLOR_PENDING" "$COLOR_IN_PROGRESS" "$COLOR_REVIEW" "$COLOR_COMPLETED" "$COLOR_REJECTED")

    # カラムデータを取得
    declare -a column_tasks
    for i in "${!columns[@]}"; do
        local status="${columns[$i]}"
        local tasks=$(tui_get_tasks_by_status "$status")
        column_tasks["$i"]="$tasks"
    done

    # カラムヘッダー描画
    for i in "${!columns[@]}"; do
        local col=$((board_col + i * col_width + i * 1))
        local title="${titles[$i]}"
        local tasks="${column_tasks[$i]}"
        local count=$(echo "$tasks" | jq 'length' 2>/dev/null | tr -d '[:space:]')
        count=${count:-0}
        local focused="false"
        [[ $i -eq $TUI_FOCUSED_COLUMN ]] && focused="true"

        tui_draw_column_header $((board_row - 2)) "$col" "$col_width" "$title" "$count" "$focused"
    done

    # カラム描画
    for i in "${!columns[@]}"; do
        local status="${columns[$i]}"
        local col=$((board_col + i * col_width + i * 1))
        local tasks="${column_tasks[$i]}"

        tui_draw_column "$board_row" "$col" "$col_width" "$board_height" "$status" "$tasks" "$TUI_SELECTED_TASK_ID"
    done

    # フッター
    tui_draw_footer

    # 選択タスク情報
    if [[ $TUI_SELECTED_TASK_ID -gt 0 ]]; then
        tui_draw_selected_task_info "$TUI_SELECTED_TASK_ID"
    fi
}

# 選択タスク情報を描画
tui_draw_selected_task_info() {
    local task_id="$1"
    local tasks_file=$(tui_get_tasks_file)

    local task=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == ($id | tonumber))' "$tasks_file" 2>/dev/null)

    if [[ -z "$task" ]]; then
        return
    fi

    local description=$(echo "$task" | jq -r '.description' 2>/dev/null)
    local agent=$(echo "$task" | jq -r '.agent' 2>/dev/null)
    local priority=$(echo "$task" | jq -r '.priority' 2>/dev/null)
    local status=$(echo "$task" | jq -r '.status' 2>/dev/null)

    local rows=$(tui_get_rows | tr -d '[:space:]')
    rows=${rows:-24}
    local info_row=$((rows - 6))

    tui_move "$info_row" 2
    printf "${COLOR_DIM}Selected: #${task_id} ${description}${NC}  "
    printf "${BOLD}$(tui_get_agent_color "$agent")${agent^}${NC}  "
    printf "$(tui_get_priority_badge "$priority")  "
    printf "$(tui_get_status_icon "$status")${status^}${NC}"
}

# =============================================================================
# リフレッシュ制御
# =============================================================================

# 画面をリフレッシュ
tui_refresh() {
    if tui_needs_redraw; then
        tui_draw_taskboard
        tui_mark_clean
    fi
}

# 強制リフレッシュ
tui_force_refresh() {
    tui_mark_dirty
    tui_refresh
}

# =============================================================================
# エクスポート
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f tui_mark_dirty
    export -f tui_is_dirty
    export -f tui_mark_clean
    export -f tui_needs_redraw
    export -f tui_draw_cell
    export -f tui_clear_cell
    export -f tui_clear_line
    export -f tui_draw_selection_cursor
    export -f tui_draw_task_card
    export -f tui_draw_task_compact
    export -f tui_draw_column_header
    export -f tui_draw_column
    export -f tui_draw_header
    export -f tui_draw_summary
    export -f tui_draw_footer
    export -f tui_draw_taskboard
    export -f tui_draw_selected_task_info
    export -f tui_refresh
    export -f tui_force_refresh
fi
