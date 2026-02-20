#!/bin/bash
# tests/verify_tui_functions.sh
# Simple unit tests for TUI functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

# Mock environment
TASKS_FILE="/tmp/test_tasks.json"
echo '{"tasks":[{"id":1,"description":"Task 1","status":"pending"},{"id":2,"description":"Task 2","status":"in_progress"}]}' > "$TASKS_FILE"

get_terminal_height() { echo 24; }
get_terminal_width() { echo 80; }

# Source required modules
source "$CLAUDE_SCRIPTS_DIR/tui-core.sh"
source "$CLAUDE_SCRIPTS_DIR/tui-keyboard.sh"

# Extract just the functions we need from dashboard.sh
eval "$(sed -n '/^get_all_task_ids()/,/^}/p' "$CLAUDE_SCRIPTS_DIR/dashboard.sh")"

passed=0
failed=0

run_test() {
    local test_name="$1"
    local command="$2"
    local expected="$3"

    echo -n "Testing: $test_name ... "
    local result
    result=$(eval "$command" 2>/dev/null)

    if [[ "$result" == "$expected" ]]; then
        echo "PASS"
        ((passed++))
    else
        echo "FAIL"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((failed++))
    fi
}

echo "========================================="
echo "TUI Functions Unit Tests"
echo "========================================="

# Test 1: get_all_task_ids returns correct IDs
run_test "get_all_task_ids" "get_all_task_ids" "1 2"

# Test 2: get_all_task_ids with empty tasks
echo '{"tasks":[]}' > "$TASKS_FILE"
run_test "get_all_task_ids (empty)" "get_all_task_ids" ""

# Test 3: get_all_task_ids with single task
echo '{"tasks":[{"id":5,"description":"Single","status":"pending"}]}' > "$TASKS_FILE"
run_test "get_all_task_ids (single)" "get_all_task_ids" "5"

# Restore original tasks for cleanup
echo '{"tasks":[{"id":1,"description":"Task 1","status":"pending"},{"id":2,"description":"Task 2","status":"in_progress"}]}' > "$TASKS_FILE"

echo "========================================="
echo "Results: $passed passed, $failed failed"
echo "========================================="

if [[ $failed -eq 0 ]]; then
    echo "✓ All tests PASSED"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
