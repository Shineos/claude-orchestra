#!/bin/bash
# TUI Keyboard Handler
#
# キーボード入力のハンドリングとキーバインディング管理

# このファイルはtui-core.shの後でsourceする必要がある

# =============================================================================
# キーコード定数
# =============================================================================

# 特殊キー
KEY_ESCAPE=$'\x1b'
KEY_ENTER=$'\x0a'
KEY_TAB=$'\x09'
KEY_SPACE=$'\x20'
KEY_BACKSPACE=$'\x7f'
KEY_DELETE=$'\x1b[3~'

# 方向キー（エスケープシーケンス）
KEY_UP=$'\x1b[A'
KEY_DOWN=$'\x1b[B'
KEY_RIGHT=$'\x1b[C'
KEY_LEFT=$'\x1b[D'

# ページキー
KEY_PAGE_UP=$'\x1b[5~'
KEY_PAGE_DOWN=$'\x1b[6~'
KEY_HOME=$'\x1b[H'
KEY_END=$'\x1b[F'

# Function keys
KEY_F1=$'\x1bOP'
KEY_F2=$'\x1bOQ'
KEY_F3=$'\x1bOR'
KEY_F4=$'\x1bOS'
KEY_F5=$'\x1b[15~'
KEY_F10=$'\x1b[21~'

# Ctrlキー
KEY_CTRL_A=$'\x01'
KEY_CTRL_B=$'\x02'
KEY_CTRL_C=$'\x03'
KEY_CTRL_D=$'\x04'
KEY_CTRL_E=$'\x05'
KEY_CTRL_F=$'\x06'
KEY_CTRL_G=$'\x07'
KEY_CTRL_L=$'\x0c'
KEY_CTRL_N=$'\x0e'
KEY_CTRL_P=$'\x10'
KEY_CTRL_Q=$'\x11'
KEY_CTRL_R=$'\x12'
KEY_CTRL_S=$'\x13'
KEY_CTRL_T=$'\x14'
KEY_CTRL_U=$'\x15'
KEY_CTRL_V=$'\x16'
KEY_CTRL_W=$'\x17'
KEY_CTRL_X=$'\x18'

# =============================================================================
# キー入力取得
# =============================================================================

# 1文字を読み取る（タイムアウト付き）
_tui_read_char() {
    local timeout="${1:-0.1}"
    local char
    IFS= read -rsn1 -t "$timeout" char
    echo "$char"
}

# エスケープシーケンスを読み取る
_tui_read_escape_sequence() {
    local seq=$'\x1b'
    local char

    # 次の文字を読み取り
    IFS= read -rsn1 -t 0.1 char || { echo "$seq"; return; }

    if [[ "$char" == "[" ]]; then
        seq="${seq}["
        # パラメータと終了文字を読み取り
        IFS= read -rsn2 -t 0.1 char || { echo "$seq"; return; }
        seq="${seq}${char}"
    elif [[ "$char" == "O" ]]; then
        seq="${seq}O"
        # Function key
        IFS= read -rsn1 -t 0.1 char || { echo "$seq"; return; }
        seq="${seq}${char}"
    else
        # ALTキー + 文字
        seq="${seq}${char}"
    fi

    echo "$seq"
}

# キー入力を取得（メイン関数）
tui_get_key() {
    local char
    char=$(_tui_read_char 1)

    if [[ -z "$char" ]]; then
        # タイムアウト（auto-update用）
        echo "TIMEOUT"
        return
    fi

    if [[ "$char" == $'\x1b' ]]; then
        # エスケープシーケンス
        _tui_read_escape_sequence
    else
        # 通常文字
        echo "$char"
    fi
}

# =============================================================================
# キー判定ユーティリティ
# =============================================================================

# キーが方向キーかどうか
tui_is_arrow_key() {
    local key="$1"
    case "$key" in
        $KEY_UP|$KEY_DOWN|$KEY_LEFT|$KEY_RIGHT)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# キーがvim-style移動キーかどうか
tui_is_vim_key() {
    local key="$1"
    case "$key" in
        h|j|k|l)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# キーが数字かどうか
tui_is_digit() {
    local key="$1"
    [[ "$key" =~ ^[0-9]$ ]]
}

# キーがCtrlキーかどうか
tui_is_ctrl_key() {
    local key="$1"
    [[ "$key" =~ ^.$ ]] && [[ "$key" < " " ]]
}

# =============================================================================
# キーコマンド定義
# =============================================================================

declare -gA TUI_KEY_BINDINGS=(
    # 移動
    ["$KEY_UP"]="cmd_move_up"
    ["k"]="cmd_move_up"
    ["$KEY_DOWN"]="cmd_move_down"
    ["j"]="cmd_move_down"
    ["$KEY_LEFT"]="cmd_move_left"
    ["h"]="cmd_move_left"
    ["$KEY_RIGHT"]="cmd_move_right"
    ["l"]="cmd_move_right"
    ["$KEY_HOME"]="cmd_move_first"
    ["$KEY_END"]="cmd_move_last"
    ["$KEY_PAGE_UP"]="cmd_page_up"
    ["$KEY_PAGE_DOWN"]="cmd_page_down"
    ["ctrl-b"]="cmd_page_up"
    ["ctrl-f"]="cmd_page_down"
    ["g"]="cmd_move_first"
    ["G"]="cmd_move_last"

    # 操作
    ["$KEY_ENTER"]="cmd_select"
    [" "]="cmd_toggle_select"
    ["s"]="cmd_start"
    ["c"]="cmd_complete"
    ["f"]="cmd_fail"
    ["r"]="cmd_reset"
    ["d"]="cmd_delete"
    ["e"]="cmd_edit"
    ["+"]="cmd_priority_up"
    ["-"]="cmd_priority_down"
    ["x"]="cmd_complete"

    # ビュー
    ["1"]="cmd_focus_column_1"
    ["2"]="cmd_focus_column_2"
    ["3"]="cmd_focus_column_3"
    ["4"]="cmd_focus_column_4"
    ["5"]="cmd_focus_column_5"
    ["a"]="cmd_show_all"
    ["p"]="cmd_filter_pending"
    ["i"]="cmd_filter_in_progress"
    ["D"]="cmd_filter_done"
    ["F"]="cmd_filter_failed"
    ["t"]="cmd_search_tags"
    ["/"]="cmd_search"

    # その他
    ["?"]="cmd_help"
    [":"]="cmd_command"
    ["R"]="cmd_refresh"
    ["A"]="cmd_toggle_auto_update"
    ["q"]="cmd_quit"
    ["$KEY_ESCAPE"]="cmd_quit"
    ["ZZ"]="cmd_quit"
)

# キーバインディングを設定
tui_bind_key() {
    local key="$1"
    local command="$2"
    TUI_KEY_BINDINGS["$key"]="$command"
}

# キーに対応するコマンドを取得
tui_get_command() {
    local key="$1"
    local command="${TUI_KEY_BINDINGS[$key]}"

    # 数字キーの場合（カラム選択）
    if tui_is_digit "$key"; then
        command="cmd_focus_column_${key}"
    fi

    echo "$command"
}

# =============================================================================
# キーボードルーパー（イベントハンドラー）
# =============================================================================

# コマンド実行者
tui_execute_command() {
    local command="$1"
    shift

    # コマンドが定義されていない場合
    if [[ -z "$command" ]]; then
        return 1
    fi

    # コマンドを実行
    if declare -f "$command" > /dev/null; then
        "$command" "$@"
        return 0
    else
        # 未定義のコマンド
        return 1
    fi
}

# デフォルトのコマンドハンドラー（オーバーライド用）
cmd_move_up() { :; }
cmd_move_down() { :; }
cmd_move_left() { :; }
cmd_move_right() { :; }
cmd_move_first() { :; }
cmd_move_last() { :; }
cmd_page_up() { :; }
cmd_page_down() { :; }

cmd_select() { :; }
cmd_toggle_select() { :; }
cmd_start() { :; }
cmd_complete() { :; }
cmd_fail() { :; }
cmd_reset() { :; }
cmd_delete() { :; }
cmd_edit() { :; }
cmd_priority_up() { :; }
cmd_priority_down() { :; }

cmd_focus_column_1() { :; }
cmd_focus_column_2() { :; }
cmd_focus_column_3() { :; }
cmd_focus_column_4() { :; }
cmd_focus_column_5() { :; }
cmd_show_all() { :; }
cmd_filter_pending() { :; }
cmd_filter_in_progress() { :; }
cmd_filter_done() { :; }
cmd_filter_failed() { :; }
cmd_search_tags() { :; }
cmd_search() { :; }

cmd_help() { :; }
cmd_command() { :; }
cmd_refresh() { :; }
cmd_toggle_auto_update() { :; }
cmd_quit() { :; }

# =============================================================================
# 入力モード管理
# =============================================================================

declare -g TUI_INPUT_MODE="normal"  # normal, insert, command, search
declare -g TUI_INPUT_BUFFER=""
declare -g TUI_INPUT_CURSOR=0

# 入力モードを設定
tui_set_input_mode() {
    local mode="$1"
    TUI_INPUT_MODE="$mode"
    TUI_INPUT_BUFFER=""
    TUI_INPUT_CURSOR=0
}

# 入力モードを取得
tui_get_input_mode() {
    echo "$TUI_INPUT_MODE"
}

# 入力バッファに文字を追加
tui_input_append() {
    local char="$1"
    TUI_INPUT_BUFFER="${TUI_INPUT_BUFFER}${char}"
    ((TUI_INPUT_CURSOR++))
}

# 入力バッファから文字を削除
tui_input_backspace() {
    if [[ $TUI_INPUT_CURSOR -gt 0 ]]; then
        local len=${#TUI_INPUT_BUFFER}
        TUI_INPUT_BUFFER="${TUI_INPUT_BUFFER:0:$((len - 1))}"
        ((TUI_INPUT_CURSOR--))
    fi
}

# 入力バッファをクリア
tui_input_clear() {
    TUI_INPUT_BUFFER=""
    TUI_INPUT_CURSOR=0
}

# 入力バッファを取得
tui_get_input_buffer() {
    echo "$TUI_INPUT_BUFFER"
}

# =============================================================================
# マクロ・キーマップ
# =============================================================================

# vim-styleの「gg」で先頭に移動
declare -g TUI_LAST_KEY=""
declare -g TUI_KEY_SEQUENCE_TIMEOUT=0.5

# キーシーケンスのチェック
tui_check_key_sequence() {
    local key="$1"
    local result=""

    case "$TUI_LAST_KEY" in
        g)
            if [[ "$key" == "g" ]]; then
                result="cmd_move_first"
            fi
            ;;
        d)
            if [[ "$key" == "d" ]]; then
                result="cmd_delete_line"
            fi
            ;;
        y)
            if [[ "$key" == "y" ]]; then
                result="cmd_yank"
            fi
            ;;
        c)
            if [[ "$key" == "c" ]]; then
                result="cmd_change"
            fi
            ;;
        Z)
            if [[ "$key" == "Z" ]]; then
                result="cmd_quit"
            fi
            ;;
    esac

    TUI_LAST_KEY="$key"
    echo "$result"
}

# =============================================================================
# エクスポート
# =============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f tui_get_key
    export -f tui_is_arrow_key
    export -f tui_is_vim_key
    export -f tui_is_digit
    export -f tui_is_ctrl_key
    export -f tui_bind_key
    export -f tui_get_command
    export -f tui_execute_command
    export -f tui_set_input_mode
    export -f tui_get_input_mode
    export -f tui_input_append
    export -f tui_input_backspace
    export -f tui_input_clear
    export -f tui_get_input_buffer
    export -f tui_check_key_sequence
fi
