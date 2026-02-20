#!/bin/bash
# test_selection_return.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.claude/scripts"
source "$SCRIPT_DIR/tui-core.sh"
source "$SCRIPT_DIR/tui-keyboard.sh"
source "$SCRIPT_DIR/dashboard.sh"

# Mock get_terminal_height if needed
get_terminal_height() { echo 24; }
setup_terminal() { stty -echo -icanon min 1 time 0; }
cleanup_terminal() { stty sane; }

trap cleanup_terminal EXIT

setup_terminal
agents="Auto(AI) frontend backend"
echo "Select 'frontend' and press Enter:"
result=$(prompt_select_horizontal "Select" "$agents" 0)
status=$?

cleanup_terminal
echo
echo "Return Status: $status"
echo "Captured Value: '$result'"

if [[ "$result" == "frontend" ]]; then
    echo "SUCCESS: Correct agent captured."
elif [[ -z "$result" ]]; then
    echo "FAILURE: Result is empty."
else
    echo "FAILURE: Captured '$result' instead of 'frontend'."
fi
