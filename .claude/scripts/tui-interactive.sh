#!/bin/bash
# TUI Interactive - Main Interactive Task Board
#
# インタラクティブなタスクボードTUI
# キーボード操作でタスク管理を行う

set -e

# =============================================================================
# ライブラリの読み込み
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"

# 依存ライブラリをsource
source "$SCRIPT_DIR/tui-core.sh"
source "$SCRIPT_DIR/tui-keyboard.sh"
source "$SCRIPT_DIR/tui-renderer.sh"
source "$SCRIPT_DIR/tui-dialogs.sh"

# =============================================================================
# グローバル変数
# =============================================================================

# 選択状態
declare -g SELECTED_TASK_ID=0
declare -g FOCUSED_COLUMN=0
declare -g CURRENT_ROW_OFFSET=0

# 自動更新
declare -g AUTO_UPDATE_ENABLED=true
declare -g AUTO_UPDATE_INTERVAL=5
declare -g LAST_UPDATE_TIME=0

# フィルター
declare -g FILTER_STATUS="all"  # all, pending, in_progress, completed, failed
declare -g SEARCH_QUERY=""

# 実行フラグ
declare -g SHOULD_EXIT=false
declare -g SHOULD_REFRESH=true

# =============================================================================
# 依存関係チェック
# =============================================================================

check_dependencies() {
    local deps=("tput" "stty" "jq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Please install:"
        echo "  macOS: brew install jq"
        echo "  Ubuntu/Debian: sudo apt install jq"
        exit 1
    fi
}

# =============================================================================
# タスク操作関数
# =============================================================================

# タスク操作コマンド（orchestrator.shを呼び出す）
_orchestrator() {
    bash "$SCRIPT_DIR/orchestrator.sh" "$@"
}

# タスクを開始
action_start_task() {
    local task_id="$1"

    if [[ "$task_id" -le 0 ]]; then
        return 1
    fi

    # orchestrator.shのstartコマンドを呼ぶ
    local output=$(_orchestrator start "$task_id" 2>&1)
    local result=$?

    if [[ $result -eq 0 ]]; then
        SHOULD_REFRESH=true
    fi

    return $result
}

# タスクを完了
action_complete_task() {
    local task_id="$1"

    if [[ "$task_id" -le 0 ]]; then
        return 1
    fi

    # 確認ダイアログ
    if tui_confirm_dialog "Complete Task" "Complete task #$task_id?" "y"; then
        local output=$(_orchestrator complete "$task_id" "TUI completion" 2>&1)
        local result=$?

        if [[ $result -eq 0 ]]; then
            SHOULD_REFRESH=true
        fi

        return $result
    fi

    return 1
}

# タスクを失敗
action_fail_task() {
    local task_id="$1"

    if [[ "$task_id" -le 0 ]]; then
        return 1
    fi

    # 理由入力ダイアログ
    local reason=$(tui_input_dialog "Fail Task" "Enter failure reason:" "" 40 5)
    local dialog_result=$?

    if [[ $dialog_result -eq 0 ]] && [[ -n "$reason" ]]; then
        local output=$(_orchestrator fail "$task_id" "$reason" 2>&1)
        local result=$?

        if [[ $result -eq 0 ]]; then
            SHOULD_REFRESH=true
        fi

        return $result
    fi

    return 1
}

# タスクをリセット
action_reset_task() {
    local task_id="$1"

    if [[ "$task_id" -le 0 ]]; then
        return 1
    fi

    local output=$(_orchestrator reset "$task_id" 2>&1)
    local result=$?

    if [[ $result -eq 0 ]]; then
        SHOULD_REFRESH=true
    fi

    return $result
}

# タスクを削除
action_delete_task() {
    local task_id="$1"

    if [[ "$task_id" -le 0 ]]; then
        return 1
    fi

    # 確認ダイアログ
    if tui_confirm_dialog "Delete Task" "Delete task #$task_id?" "n"; then
        # jqでタスクを削除
        local tasks_file="$CLAUDE_DIR/tasks.json"
        local temp_file=$(mktemp)

        jq --arg id "$task_id" 'del(.tasks[] | select(.id == ($id | tonumber)))' "$tasks_file" > "$temp_file"
        mv "$temp_file" "$tasks_file"

        SHOULD_REFRESH=true
        return 0
    fi

    return 1
}

# =============================================================================
# タスク選択・移動
# =============================================================================

# すべてのタスクIDをステータス順に取得
get_all_task_ids() {
    local tasks_file="$CLAUDE_DIR/tasks.json"

    local order=("pending" "in_progress" "review_needed" "completed" "rejected")

    for status in "${order[@]}"; do
        jq -r --arg status "$status" \
            '.tasks[] | select(.status == $status or ($status == "rejected" and .status == "failed")) | .id' \
            "$tasks_file" 2>/dev/null
    done
}

# 次のタスクIDを取得
get_next_task_id() {
    local current_id="$1"

    if [[ "$current_id" -le 0 ]]; then
        # 最初のタスクを取得
        get_all_task_ids | head -1
        return
    fi

    local found=false
    get_all_task_ids | while read -r task_id; do
        if [[ "$found" == "true" ]]; then
            echo "$task_id"
            return
        fi
        if [[ "$task_id" == "$current_id" ]]; then
            found=true
        fi
    done
}

# 前のタスクIDを取得
get_prev_task_id() {
    local current_id="$1"
    local prev_id=""

    get_all_task_ids | while read -r task_id; do
        if [[ "$task_id" == "$current_id" ]]; then
            if [[ -n "$prev_id" ]]; then
                echo "$prev_id"
            fi
            return
        fi
        prev_id="$task_id"
    done
}

# 最初のタスクIDを取得
get_first_task_id() {
    get_all_task_ids | head -1
}

# 最後のタスクIDを取得
get_last_task_id() {
    get_all_task_ids | tail -1
}

# 選択タスクを次に移動
move_selection_next() {
    SELECTED_TASK_ID=$(get_next_task_id "$SELECTED_TASK_ID")
    SHOULD_REFRESH=true
}

# 選択タスクを前に移動
move_selection_prev() {
    SELECTED_TASK_ID=$(get_prev_task_id "$SELECTED_TASK_ID")

    if [[ -z "$SELECTED_TASK_ID" ]]; then
        SELECTED_TASK_ID=$(get_first_task_id)
    fi

    SHOULD_REFRESH=true
}

# 選択タスクを最初に移動
move_selection_first() {
    SELECTED_TASK_ID=$(get_first_task_id)
    SHOULD_REFRESH=true
}

# 選択タスクを最後に移動
move_selection_last() {
    SELECTED_TASK_ID=$(get_last_task_id)
    SHOULD_REFRESH=true
}

# =============================================================================
# カラム操作
# =============================================================================

# 次のカラムに移動
move_column_next() {
    FOCUSED_COLUMN=$(( (FOCUSED_COLUMN + 1) % 5 ))
    SHOULD_REFRESH=true
}

# 前のカラムに移動
move_column_prev() {
    FOCUSED_COLUMN=$(( (FOCUSED_COLUMN - 1 + 5) % 5 ))
    SHOULD_REFRESH=true
}

# 指定カラムに移動
move_column_to() {
    local col=$1
    if [[ $col -ge 0 ]] && [[ $col -le 4 ]]; then
        FOCUSED_COLUMN=$col
        SHOULD_REFRESH=true
    fi
}

# =============================================================================
# タスク詳細表示
# =============================================================================

show_task_details() {
    if [[ $SELECTED_TASK_ID -le 0 ]]; then
        return
    fi

    local result=$(tui_task_detail_dialog "$SELECTED_TASK_ID")

    case "$result" in
        start)
            action_start_task "$SELECTED_TASK_ID"
            ;;
        complete)
            action_complete_task "$SELECTED_TASK_ID"
            ;;
        fail*)
            local reason="${result#fail:}"
            if [[ -n "$reason" ]]; then
                _orchestrator fail "$SELECTED_TASK_ID" "$reason"
                SHOULD_REFRESH=true
            fi
            ;;
        reset)
            action_reset_task "$SELECTED_TASK_ID"
            ;;
        close)
            # 何もしない
            ;;
    esac
}

# =============================================================================
# コマンドハンドラー（キーバインディング用）
# =============================================================================

# 移動コマンド
cmd_move_up() { move_selection_prev; }
cmd_move_down() { move_selection_next; }
cmd_move_left() { move_column_prev; }
cmd_move_right() { move_column_next; }
cmd_move_first() { move_selection_first; }
cmd_move_last() { move_selection_last; }
cmd_page_up() { move_selection_prev; move_selection_prev; move_selection_prev; }
cmd_page_down() { move_selection_next; move_selection_next; move_selection_next; }

# 操作コマンド
cmd_select() { show_task_details; }
cmd_start() { action_start_task "$SELECTED_TASK_ID"; }
cmd_complete() { action_complete_task "$SELECTED_TASK_ID"; }
cmd_fail() { action_fail_task "$SELECTED_TASK_ID"; }
cmd_reset() { action_reset_task "$SELECTED_TASK_ID"; }
cmd_delete() { action_delete_task "$SELECTED_TASK_ID"; }
cmd_toggle_select() { :; }  # TODO: 複数選択実装時に実装
cmd_edit() { :; }  # TODO: 編集ダイアログ実装時に実装
cmd_priority_up() { :; }  # TODO: 優先度変更実装時に実装
cmd_priority_down() { :; }  # TODO: 優先度変更実装時に実装

# カラムフォーカスコマンド
cmd_focus_column_1() { move_column_to 0; }
cmd_focus_column_2() { move_column_to 1; }
cmd_focus_column_3() { move_column_to 2; }
cmd_focus_column_4() { move_column_to 3; }
cmd_focus_column_5() { move_column_to 4; }

# フィルターコマンド
cmd_show_all() { FILTER_STATUS="all"; SHOULD_REFRESH=true; }
cmd_filter_pending() { FILTER_STATUS="pending"; SHOULD_REFRESH=true; }
cmd_filter_in_progress() { FILTER_STATUS="in_progress"; SHOULD_REFRESH=true; }
cmd_filter_done() { FILTER_STATUS="completed"; SHOULD_REFRESH=true; }
cmd_filter_failed() { FILTER_STATUS="failed"; SHOULD_REFRESH=true; }
cmd_search_tags() { :; }  # TODO: タグ検索実装時に実装
cmd_search() {  # TODO: 検索ダイアログ実装時に実装
    local query=$(tui_input_dialog "Search" "Search query:" "" 40 5)
    if [[ $? -eq 0 ]]; then
        SEARCH_QUERY="$query"
        SHOULD_REFRESH=true
    fi
}

# その他コマンド
cmd_help() { tui_help_dialog; SHOULD_REFRESH=true; }
cmd_command() { :; }  # TODO: コマンドモード実装時に実装
cmd_refresh() { SHOULD_REFRESH=true; tui_force_refresh; }
cmd_toggle_auto_update() {
    if [[ "$AUTO_UPDATE_ENABLED" == "true" ]]; then
        AUTO_UPDATE_ENABLED=false
    else
        AUTO_UPDATE_ENABLED=true
    fi
    SHOULD_REFRESH=true
}
cmd_quit() { SHOULD_EXIT=true; }

# =============================================================================
# メインループ
# =============================================================================

# メインイベントループ
main_loop() {
    SHOULD_EXIT=false
    SHOULD_REFRESH=true
    LAST_UPDATE_TIME=0

    # 最初のタスクを選択
    SELECTED_TASK_ID=$(get_first_task_id)

    while [[ "$SHOULD_EXIT" != "true" ]]; do
        # 自動更新チェック
        local current_time=$(date +%s)
        local elapsed=$((current_time - LAST_UPDATE_TIME))

        if [[ "$AUTO_UPDATE_ENABLED" == "true" ]] && [[ $elapsed -ge $AUTO_UPDATE_INTERVAL ]]; then
            SHOULD_REFRESH=true
            LAST_UPDATE_TIME=$current_time
        fi

        # 画面更新
        if [[ "$SHOULD_REFRESH" == "true" ]]; then
            # 選択状態をグローバル変数に設定
            TUI_SELECTED_TASK_ID=$SELECTED_TASK_ID
            TUI_FOCUSED_COLUMN=$FOCUSED_COLUMN

            tui_force_refresh
            SHOULD_REFRESH=false
        fi

        # キー入力待ち（タイムアウト付き）
        local key=$(tui_get_key)

        # タイムアウトの場合はループ継続
        if [[ "$key" == "TIMEOUT" ]]; then
            continue
        fi

        # キーシーケンスチェック
        local sequence_cmd=$(tui_check_key_sequence "$key")
        if [[ -n "$sequence_cmd" ]]; then
            tui_execute_command "$sequence_cmd"
            continue
        fi

        # コマンド取得・実行
        local command=$(tui_get_command "$key")
        if [[ -n "$command" ]]; then
            tui_execute_command "$command"
        fi
    done
}

# =============================================================================
# エントリーポイント
# =============================================================================

main() {
    # 依存関係チェック
    check_dependencies

    # 端末初期化
    tui_init_terminal

    # 最初の描画
    tui_mark_dirty

    # メインループ
    main_loop

    # 終了処理
    tui_cleanup_terminal

    # 最終ステータス表示
    echo "TUI exited"
}

# スクリプトとして実行された場合のみメイン処理を実行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
