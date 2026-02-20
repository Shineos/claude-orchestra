#!/bin/bash
# tests/verify_final_fixes.sh

SCRIPT_DIR="/Users/grace/dev/shineos/claude-orchestra/.claude/scripts"
source "$SCRIPT_DIR/tui-core.sh"
source "$SCRIPT_DIR/tui-keyboard.sh"
source "$SCRIPT_DIR/dashboard.sh"

echo "Checking KEY_ENTER value..."
if [[ "$KEY_ENTER" == "ENTER" ]]; then
    echo "✓ KEY_ENTER is symbolic 'ENTER'"
else
    echo "✗ KEY_ENTER is '$KEY_ENTER', expected 'ENTER'"
    exit 1
fi

echo "Checking multi-byte cursor length calculation..."
prompt="表示対象ID (v)"
# get_display_width は以前作成したはずだが、dashboard.shにあるか確認
if declare -f get_display_width >/dev/null; then
    width=$(get_display_width "$prompt")
    echo "Display width of '$prompt': $width"
    # "表示対象ID" (10) + " (v)" (4) = 14
    if [[ $width -gt 10 && $width -lt 20 ]]; then
        echo "✓ Display width seems correct ($width)"
    else
        echo "✗ Display width seems incorrect ($width)"
        exit 1
    fi
else
    echo "✗ get_display_width not found"
    exit 1
fi

echo "Checking tui_get_key for CR and LF..."

# tui_get_key は内部で _tui_read_char を呼ぶ
# モックしてテスト
_tui_read_char() {
    # CR (\x0d) をシミュレート
    printf "\x0d_"
}

result=$(tui_get_key)
if [[ "${result%_}" == "ENTER" ]]; then
    echo "✓ CR normalized to ENTER"
else
    echo "✗ CR normalized to '${result%_}'"
    exit 1
fi

_tui_read_char() {
    # LF (\x0a) をシミュレート
    printf "\x0a_"
}

result=$(tui_get_key)
if [[ "${result%_}" == "ENTER" ]]; then
    echo "✓ LF normalized to ENTER"
else
    echo "✗ LF normalized to '${result%_}'"
    exit 1
fi

_tui_read_char() {
    # 空文字 (IFS等で吸収された場合) をシミュレート
    printf "_"
}

result=$(tui_get_key)
if [[ "${result%_}" == "ENTER" ]]; then
    echo "✓ Swallowed char normalized to ENTER"
else
    echo "✗ Swallowed char normalized to '${result%_}'"
    exit 1
fi

echo "All final verification tests passed!"
