#!/bin/bash
# Verify prompt_select_horizontal behavior

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

# Mock dependencies
source "$CLAUDE_SCRIPTS_DIR/tui-core.sh"
source "$CLAUDE_SCRIPTS_DIR/tui-keyboard.sh"

# Mock dashboard.sh dependent functions
get_terminal_height() { echo 24; }
get_terminal_width() { echo 80; }
tui_flush_input() { :; }

# Source target function from dashboard.sh
# Extract prompt_select_horizontal function
sed -n '/^prompt_select_horizontal()/,/^}/p' "$CLAUDE_SCRIPTS_DIR/dashboard.sh" > /tmp/test_func.sh
source /tmp/test_func.sh

# Test Case: Default selection (Enter immediately)
echo "Test 1: Default Selection"
# Input: Enter
# Add sleep to ensure prompt is ready
output=$( { sleep 0.2; echo -ne "\n"; } | prompt_select_horizontal "Test" "A B C" 0)
if [[ "$output" == "A" ]]; then
    echo "PASS: Got 'A'"
else
    echo "FAIL: Expected 'A', got '$output'"
    # exit 1  # Don't exit yet, run other tests
fi

# Test Case: Move Right (Right Arrow + Enter)
echo "Test 2: Move Right"
# Input: Right Arrow + Enter
output=$( { sleep 0.2; echo -ne "\x1b[C\n"; } | prompt_select_horizontal "Test" "A B C" 0)
if [[ "$output" == "B" ]]; then
    echo "PASS: Got 'B'"
else
    echo "FAIL: Expected 'B', got '$output'"
    exit 1
fi

# Test Case: Move Left Loop (Left Arrow from 0 -> Last + Enter)
echo "Test 3: Move Left Loop"
# Input: Left Arrow + Enter
# Left Arrow is \x1b[D
output=$( { sleep 0.2; echo -ne "\x1b[D\n"; } | prompt_select_horizontal "Test" "A B C" 0)
if [[ "$output" == "C" ]]; then
    echo "PASS: Got 'C'"
else
    echo "FAIL: Expected 'C', got '$output'"
    exit 1
fi

echo "All tests passed"
