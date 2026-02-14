#!/bin/bash
# tests/test_enter_fix.sh - Enterキーの修正とタスクID入力の検証

SCRIPT_DIR="/Users/grace/dev/shineos/claude-orchestra/.claude/scripts"
source "$SCRIPT_DIR/tui-keyboard.sh"
source "$SCRIPT_DIR/tui-core.sh"
source "$SCRIPT_DIR/dashboard.sh"

# モックの作成
get_terminal_height() { echo 24; }
get_terminal_width() { echo 80; }

# tui_get_key をモックして特定の入力をシミュレートする関数
simulate_input() {
    local input_str="$1"
    local idx=0
    
    tui_get_key() {
        if [[ $idx -lt ${#input_str} ]]; then
            local char="${input_str:$idx:1}"
            ((idx++))
            printf "%s_" "$char"
        else
            # Enterをシミュレート
            printf "%s_" "ENTER"
        fi
    }
}

echo "Testing prompt_input with ID '1'..."
simulate_input "1"

# prompt_input を呼び出し（出力先をリダイレクトしないとTUI描画が混ざる）
# 実際には stdout に ID が出力されるはず
result=$(prompt_input "対象ID" 2>/dev/null)

if [[ "$result" == "1" ]]; then
    echo "✓ Success: prompt_input returned '$result'"
else
    echo "✗ Failure: prompt_input returned '$result', expected '1'"
    exit 1
fi

echo "Testing prompt_input cancellation with ESC..."
tui_get_key() {
    printf "KEY_ESCAPE_"
}
# KEY_ESCAPE が \x1b なので、tui-keyboard.sh の定義に合わせる必要があるが、
# 現在の定義は KEY_ESCAPE=$'\x1b'
tui_get_key() {
    printf "%s_" $'\x1b'
}

if ! prompt_input "対象ID" >/dev/null 2>&1; then
    echo "✓ Success: prompt_input correctly cancelled with ESC"
else
    echo "✗ Failure: prompt_input did not cancel with ESC"
    exit 1
fi

echo "All tests passed!"
