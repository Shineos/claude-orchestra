#!/bin/bash
# TUI Dialogs
#
# ダイアログ表示関数
# 確認ダイアログ、入力ダイアログ、タスク詳細モーダルなど

# このファイルはtui-core.shとtui-keyboard.shの後でsourceする必要がある

# =============================================================================
# ダイアログ管理
# =============================================================================

declare -g TUI_DIALOG_STACK=()
declare -g TUI_DIALOG_ACTIVE=false

# ダイアログを開く
tui_open_dialog() {
    local dialog_type="$1"
    shift

    # 現在の画面を保存
    tui_save_cursor

    # ダイアログをスタックにプッシュ
    TUI_DIALOG_STACK+=("$dialog_type")
    TUI_DIALOG_ACTIVE=true
}

# ダイアログを閉じる
tui_close_dialog() {
    # スタックからポップ
    unset 'TUI_DIALOG_STACK[-1]'

    if [[ ${#TUI_DIALOG_STACK[@]} -eq 0 ]]; then
        TUI_DIALOG_ACTIVE=false
    fi

    # 画面を復元
    tui_restore_cursor
    tui_mark_dirty
}

# ダイアログがアクティブかどうか
tui_is_dialog_active() {
    [[ "$TUI_DIALOG_ACTIVE" == "true" ]]
}

# =============================================================================
# 確認ダイアログ
# =============================================================================

# 確認ダイアログを表示
tui_confirm_dialog() {
    local title="$1"
    local message="$2"
    local default="${3:-n}"
    local width=${4:-50}
    local height=${5:-8}

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)
    local dialog_row=$(( (rows - height) / 2 ))
    local dialog_col=$(( (cols - width) / 2 ))

    # 背景を暗くする（オプション効果）
    tui_draw_overlay "$dialog_row" "$dialog_col" "$width" "$height"

    # ダイアログボックス
    tui_box "$dialog_row" "$dialog_col" "$width" "$height" "$title" "$COLOR_WARNING"

    # メッセージを表示（複数行対応）
    local message_row=$((dialog_row + 2))
    local current_col=$((dialog_col + 4))
    local max_width=$((width - 8))

    echo "$message" | while IFS= read -r line; do
        tui_move "$message_row" "$current_col"
        local truncated=$(tui_truncate "$line" "$max_width")
        printf "${COLOR_WARNING}${truncated}${NC}"
        ((message_row++))
    done

    # ボタン
    local button_row=$((dialog_row + height - 2))
    local yes_color="${COLOR_SUCCESS}"
    local no_color="${COLOR_ERROR}"

    if [[ "$default" == "y" ]]; then
        yes_color="${BOLD}${COLOR_SUCCESS}"
    else
        no_color="${BOLD}${COLOR_ERROR}"
    fi

    tui_move "$button_row" $((dialog_col + width / 2 - 12))
    printf "[${yes_color}y${NC}:Yes] [${no_color}n${NC}:No]"

    # 入力待ち
    local result
    while true; do
        local key=$(tui_get_key)

        case "$key" in
            y|Y)
                result=0
                break
                ;;
            n|N|$KEY_ENTER)
                result=1
                break
                ;;
            $KEY_ESCAPE|q)
                result=2
                break
                ;;
        esac
    done

    # ダイアログを閉じて復元
    tui_restore_cursor
    tui_mark_dirty
    tui_refresh

    return $result
}

# =============================================================================
# 入力ダイアログ
# =============================================================================

# 入力ダイアログを表示
tui_input_dialog() {
    local title="$1"
    local prompt="$2"
    local default_value="${3:-}"
    local width=${4:-50}
    local height=${5:-6}
    local password="${6:-false}"

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)
    local dialog_row=$(( (rows - height) / 2 ))
    local dialog_col=$(( (cols - width) / 2 ))

    # 背景を暗くする
    tui_draw_overlay "$dialog_row" "$dialog_col" "$width" "$height"

    # ダイアログボックス
    tui_box "$dialog_row" "$dialog_col" "$width" "$height" "$title" "$COLOR_PRIMARY"

    # プロンプト
    tui_move $((dialog_row + 2)) $((dialog_col + 4))
    printf "${BOLD}${prompt}${NC}"

    # 入力欄
    local input_row=$((dialog_row + 3))
    local input_col=$((dialog_col + 4))
    local input_width=$((width - 8))

    tui_move "$input_row" "$input_col"
    printf "[${COLOR_PRIMARY}"

    # 入力ループ
    local input="$default_value"
    local cursor_pos=${#default_value}

    while true; do
        # 入力欄を描画
        tui_move "$input_row" "$input_col"
        printf "${COLOR_PRIMARY}[${NC}"

        if [[ "$password" == "true" ]]; then
            # パスワードモード（*で表示）
            local masked=""
            local i=0
            while [[ $i -lt ${#input} ]]; do
                masked="${masked}*"
                ((i++))
            done
            printf "%s" "$masked"
        else
            # 通常モード
            printf "${input}"
        fi

        # 残りをスペースで埋める
        local remaining=$((input_width - ${#input}))
        printf "%${remaining}s${COLOR_PRIMARY}]${NC} "

        # カーソル位置
        tui_move "$input_row" $((input_col + cursor_pos + 2))
        tui_show_cursor

        local key=$(tui_get_key)

        case "$key" in
            $KEY_ENTER)
                tui_hide_cursor
                echo "$input"
                return 0
                ;;
            $KEY_ESCAPE)
                tui_hide_cursor
                return 1
                ;;
            $KEY_BACKSPACE)
                if [[ $cursor_pos -gt 0 ]]; then
                    input="${input:0:$((cursor_pos - 1))}${input:$cursor_pos}"
                    ((cursor_pos--))
                fi
                ;;
            TIMEOUT)
                continue
                ;;
            $KEY_CTRL_C)
                tui_hide_cursor
                return 1
                ;;
            *)
                # 通常文字
                if [[ ${#key} -eq 1 ]] && [[ "$key" =~ [[:print:]] ]]; then
                    if [[ ${#input} -lt $input_width ]]; then
                        input="${input:0:$cursor_pos}${key}${input:$cursor_pos}"
                        ((cursor_pos++))
                    fi
                fi
                ;;
        esac
    done
}

# =============================================================================
# オーバーレイ描画
# =============================================================================

# 背景を暗くするオーバーレイを描画
tui_draw_overlay() {
    local dialog_row=$1
    local dialog_col=$2
    local width=$3
    local height=$4

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)

    # 半透明の背景効果（端末によっては動作しない場合あり）
    # tput の dim 機能を使用
    printf "${DIM}"

    local row=0
    while [[ $row -lt $rows ]]; do
        tui_move "$row" 0
        printf "%${cols}s" " "
        ((row++))
    done

    printf "${NC}"
}

# =============================================================================
# タスク詳細モーダル
# =============================================================================

# タスク詳細モーダルを表示
tui_task_detail_dialog() {
    local task_id="$1"
    local tasks_file=$(tui_get_tasks_file)

    local task=$(jq -r --arg id "$task_id" ".tasks[] | select(.id == (\$id | tonumber))" "$tasks_file")

    if [[ -z "$task" ]]; then
        return 1
    fi

    local description=$(echo "$task" | jq -r '.description')
    local agent=$(echo "$task" | jq -r '.agent')
    local status=$(echo "$task" | jq -r '.status')
    local priority=$(echo "$task" | jq -r '.priority')
    local dependencies=$(echo "$task" | jq -r '.dependencies[]?' | paste -sd ", " -)
    local created_at=$(echo "$task" | jq -r '.created_at')
    local started_at=$(echo "$task" | jq -r ".started_at // \"N/A\"")
    local completed_at=$(echo "$task" | jq -r ".completed_at // \"N/A\"")

    local width=60
    local height=20

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)
    local dialog_row=$(( (rows - height) / 2 ))
    local dialog_col=$(( (cols - width) / 2 ))

    # 背景オーバーレイ
    tui_draw_overlay "$dialog_row" "$dialog_col" "$width" "$height"

    # モーダルボックス
    tui_box "$dialog_row" "$dialog_col" "$width" "$height" "📋 Task Details" "$COLOR_INFO"

    # タスク情報表示
    local info_row=$((dialog_row + 2))
    local info_col=$((dialog_col + 4))
    local field_width=15

    # IDと説明
    tui_move "$info_row" "$info_col"
    printf "${BOLD}ID:${NC}           #${task_id}"

    tui_move $((info_row + 1)) "$info_col"
    printf "${BOLD}Description:${NC}  ${description}"

    # Agent, Status, Priority
    tui_move $((info_row + 3)) "$info_col"
    printf "${BOLD}Agent:${NC}        ${BOLD}$(tui_get_agent_color "$agent")${agent^}${NC}"

    tui_move $((info_row + 4)) "$info_col"
    printf "${BOLD}Status:${NC}       $(tui_get_status_icon "$status") ${status^}"

    tui_move $((info_row + 5)) "$info_col"
    printf "${BOLD}Priority:${NC}     $(tui_get_priority_badge "$priority") ${priority^}"

    # Dependencies
    if [[ -n "$dependencies" ]]; then
        tui_move $((info_row + 7)) "$info_col"
        printf "${BOLD}Dependencies:${NC}  ${dependencies}"
    fi

    # Timeline
    tui_move $((info_row + 9)) "$info_col"
    printf "${BOLD}📅 Timeline${NC}"

    tui_move $((info_row + 10)) "$info_col"
    printf "  Created:    ${created_at}"

    if [[ "$started_at" != "N/A" ]] && [[ "$started_at" != "null" ]]; then
        tui_move $((info_row + 11)) "$info_col"
        printf "  Started:    ${started_at}"
    fi

    if [[ "$completed_at" != "N/A" ]] && [[ "$completed_at" != "null" ]]; then
        tui_move $((info_row + 12)) "$info_col"
        printf "  Completed:  ${completed_at}"
    fi

    # Notes
    local notes=$(echo "$task" | jq -r ".notes[]?.text // empty")
    if [[ -n "$notes" ]]; then
        tui_move $((info_row + 14)) "$info_col"
        printf "${BOLD}📝 Notes${NC}"

        local note_row=$((info_row + 15))
        echo "$notes" | while IFS= read -r note; do
            tui_move "$note_row" $((info_col + 2))
            printf "• ${note}"
            ((note_row++))
        done
    fi

    # アクションボタン
    local button_row=$((dialog_row + height - 2))
    tui_move "$button_row" $((dialog_col + width / 2 - 20))
    printf "[s:Start] [c:Complete] [f:Fail] [r:Reset] [Esc:Close]"

    # 入力待ちループ
    while true; do
        local key=$(tui_get_key)

        case "$key" in
            s)
                # Start task
                tui_close_dialog
                return "start"
                ;;
            c)
                # Complete task
                tui_close_dialog
                return "complete"
                ;;
            f)
                # Fail task
                local reason=$(tui_input_dialog "Fail Task" "Reason:" "" 40 5)
                if [[ $? -eq 0 ]]; then
                    tui_close_dialog
                    echo "fail:$reason"
                    return "fail"
                fi
                ;;
            r)
                # Reset task
                tui_close_dialog
                return "reset"
                ;;
            $KEY_ESCAPE|q)
                tui_close_dialog
                return "close"
                ;;
        esac
    done
}

# =============================================================================
# ヘルプダイアログ
# =============================================================================

# キーボードヘルプダイアログを表示
tui_help_dialog() {
    local width=60
    local height=28

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)
    local dialog_row=$(( (rows - height) / 2 ))
    local dialog_col=$(( (cols - width) / 2 ))

    # 背景オーバーレイ
    tui_draw_overlay "$dialog_row" "$dialog_col" "$width" "$height"

    # ヘルプボックス
    tui_box "$dialog_row" "$dialog_col" "$width" "$height" "❓ Keyboard Help" "$COLOR_INFO"

    local help_row=$((dialog_row + 2))
    local help_col=$((dialog_col + 4))
    local col1_width=25
    local col2_start=30

    # Movement
    tui_move "$help_row" "$help_col"
    printf "${BOLD}${COLOR_PRIMARY}MOVEMENT${NC}"

    tui_move $((help_row + 1)) "$help_col"
    printf "↑/k     Move up"
    tui_move $((help_row + 1)) $((help_col + col2_start))
    printf "↓/j     Move down"

    tui_move $((help_row + 2)) "$help_col"
    printf "←/h     Prev column"
    tui_move $((help_row + 2)) $((help_col + col2_start))
    printf "→/l     Next column"

    tui_move $((help_row + 3)) "$help_col"
    printf "Home     First task"
    tui_move $((help_row + 3)) $((help_col + col2_start))
    printf "End      Last task"

    # Task Actions
    tui_move $((help_row + 5)) "$help_col"
    printf "${BOLD}${COLOR_PRIMARY}TASK ACTIONS${NC}"

    tui_move $((help_row + 6)) "$help_col"
    printf "Enter    View details"
    tui_move $((help_row + 6)) $((help_col + col2_start))
    printf "Space    Select/Deselect"

    tui_move $((help_row + 7)) "$help_col"
    printf "s        Start task"
    tui_move $((help_row + 7)) $((help_col + col2_start))
    printf "c        Complete task"

    tui_move $((help_row + 8)) "$help_col"
    printf "f        Fail task"
    tui_move $((help_row + 8)) $((help_col + col2_start))
    printf "r        Reset task"

    tui_move $((help_row + 9)) "$help_col"
    printf "+        Increase priority"
    tui_move $((help_row + 9)) $((help_col + col2_start))
    printf "-        Decrease priority"

    # View Filters
    tui_move $((help_row + 11)) "$help_col"
    printf "${BOLD}${COLOR_PRIMARY}VIEW FILTERS${NC}"

    tui_move $((help_row + 12)) "$help_col"
    printf "1-5      Focus column"
    tui_move $((help_row + 12)) $((help_col + col2_start))
    printf "a        Show all"

    tui_move $((help_row + 13)) "$help_col"
    printf "p        Pending only"
    tui_move $((help_row + 13)) $((help_col + col2_start))
    printf "i        In Progress only"

    tui_move $((help_row + 14)) "$help_col"
    printf "d        Done only"
    tui_move $((help_row + 14)) $((help_col + col2_start))
    printf "F        Failed only"

    # Other
    tui_move $((help_row + 16)) "$help_col"
    printf "${BOLD}${COLOR_PRIMARY}OTHER${NC}"

    tui_move $((help_row + 17)) "$help_col"
    printf "?        Show this help"
    tui_move $((help_row + 17)) $((help_col + col2_start))
    printf "R        Refresh"

    tui_move $((help_row + 18)) "$help_col"
    printf "A        Toggle auto-update"
    tui_move $((help_row + 18)) $((help_col + col2_start))
    printf "q        Quit"

    tui_move $((help_row + 19)) "$help_col"
    printf "Esc      Close modal"
    tui_move $((help_row + 19)) $((help_col + col2_start))
    printf "Ctrl+C   Force quit"

    # Footer
    local button_row=$((dialog_row + height - 2))
    tui_move "$button_row" $((dialog_col + width / 2 - 6))
    printf "[Esc:Close]"

    # 入力待ち
    while true; do
        local key=$(tui_get_key)
        case "$key" in
            $KEY_ESCAPE|q|$KEY_ENTER)
                break
                ;;
        esac
    done

    # ダイアログを閉じる
    tui_restore_cursor
    tui_mark_dirty
    tui_refresh
}

# =============================================================================
# エラーダイアログ
# =============================================================================

# エラーダイアログを表示
tui_error_dialog() {
    local title="$1"
    local message="$2"

    local width=50
    local height=6

    local rows=$(tui_get_rows)
    local cols=$(tui_get_cols)
    local dialog_row=$(( (rows - height) / 2 ))
    local dialog_col=$(( (cols - width) / 2 ))

    # 背景オーバーレイ
    tui_draw_overlay "$dialog_row" "$dialog_col" "$width" "$height"

    # エラーダイアログボックス
    tui_box "$dialog_row" "$dialog_col" "$width" "$height" "$title" "$COLOR_ERROR"

    # メッセージ
    tui_move $((dialog_row + 2)) $((dialog_col + 4))
    printf "${BOLD}${COLOR_ERROR}${message}${NC}"

    # OKボタン
    local button_row=$((dialog_row + height - 2))
    tui_move "$button_row" $((dialog_col + width / 2 - 4))
    printf "[${BOLD}Enter${NC}:OK]"

    # 入力待ち
    while true; do
        local key=$(tui_get_key)
        case "$key" in
            $KEY_ESCAPE|$KEY_ENTER|q)
                break
                ;;
        esac
    done

    # ダイアログを閉じる
    tui_restore_cursor
    tui_mark_dirty
    tui_refresh
}

# =============================================================================
# エクスポート
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f tui_open_dialog
    export -f tui_close_dialog
    export -f tui_is_dialog_active
    export -f tui_confirm_dialog
    export -f tui_input_dialog
    export -f tui_draw_overlay
    export -f tui_task_detail_dialog
    export -f tui_help_dialog
    export -f tui_error_dialog
fi
