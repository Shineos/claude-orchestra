#!/bin/bash
# tests/verify_bottom_interactions.sh
# Updated version with better mocking and non-interactive testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

# Mock environment variables
TASKS_FILE="/tmp/test_tasks.json"
echo '{"tasks":[{"id":1,"description":"Task 1","status":"pending"},{"id":2,"description":"Task 2","status":"in_progress"}]}' > "$TASKS_FILE"

get_terminal_height() { echo 24; }
get_terminal_width() { echo 80; }
tui_flush_input() { :; }
setup_terminal() { :; }
cleanup_terminal() { :; }
draw_dashboard() { :; }
show_message() { echo "MSG: $1"; }
CLAUDE_DIR="/tmp"
stty() { :; }
tui_clear() { :; }

# Create mock orchestrator
ORCHESTRATOR="/tmp/mock_orch.sh"
cat > "$ORCHESTRATOR" << 'EOF'
#!/bin/bash
case "$1" in
    start)
        python3 -c "import json; data=json.load(open('$TASKS_FILE')); [t.__setitem__('status', 'in_progress') for t in data['tasks'] if t['id']==int('$2')]; json.dump(data, open('$TASKS_FILE', 'w'), indent=2)"
        echo "タスク #$2 を開始しました"
        ;;
    complete)
        python3 -c "import json; data=json.load(open('$TASKS_FILE')); [t.__setitem__('status', 'done') for t in data['tasks'] if t['id']==int('$2')]; json.dump(data, open('$TASKS_FILE', 'w'), indent=2)"
        echo "タスク #$2 を完了しました"
        ;;
    delete)
        python3 -c "import json; data=json.load(open('$TASKS_FILE')); data.__setitem__('tasks', [t for t in data['tasks'] if t['id']!=int('$2')]); json.dump(data, open('$TASKS_FILE', 'w'), indent=2)"
        echo "タスク #$2 を削除しました"
        ;;
    update)
        python3 -c "import json; data=json.load(open('$TASKS_FILE')); [t.__setitem__('description', '$3') for t in data['tasks'] if t['id']==int('$2')]; json.dump(data, open('$TASKS_FILE', 'w'), indent=2)"
        echo "タスク #$2 を更新しました"
        ;;
esac
EOF
chmod +x "$ORCHESTRATOR"

# Source TUI helpers
source "$CLAUDE_SCRIPTS_DIR/tui-core.sh"
source "$CLAUDE_SCRIPTS_DIR/tui-keyboard.sh"

# Extract only necessary functions from dashboard.sh
awk '
/^get_display_width\(\)/ { in_func=1; print; next }
/^truncate_string\(\)/ { in_func=1; print; next }
/^repeat_space\(\)/ { in_func=1; print; next }
/^read_key\(\)/ { in_func=1; print; next }
/^prompt_input\(\)/ { in_func=1; print; next }
/^prompt_edit_bottom\(\)/ { in_func=1; print; next }
/^prompt_select_horizontal\(\)/ { in_func=1; print; next }
/^get_all_task_ids\(\)/ { in_func=1; print; next }
/^start_task_interactive\(\)/ { in_func=1; print; next }
/^complete_task_interactive\(\)/ { in_func=1; print; next }
/^delete_task_interactive\(\)/ { in_func=1; print; next }
/^edit_task_interactive\(\)/ { in_func=1; print; next }

in_func && /^}$/ { print; in_func=0; next }
in_func { print; next }
' "$CLAUDE_SCRIPTS_DIR/dashboard.sh" > /tmp/test_funcs.sh

source /tmp/test_funcs.sh

echo "========================================="
echo "TUI Bottom Interactions Tests"
echo "========================================="

passed=0
failed=0

# Test 1: get_all_task_ids
echo -n "Test 1: get_all_task_ids ... "
if [[ "$(get_all_task_ids)" == "1 2" ]]; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    ((failed++))
fi

# Test 2: start_task_interactive with mocked input
echo -n "Test 2: start_task_interactive ... "
output=$(echo "" | start_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #1 を開始しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    ((failed++))
fi

# Test 3: complete_task_interactive
echo -n "Test 3: complete_task_interactive ... "
output=$(echo "" | complete_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #1 を完了しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    ((failed++))
fi

# Test 4: edit_task_interactive
echo -n "Test 4: edit_task_interactive ... "
output=$(printf "\nNew Description\n" | edit_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #2 を更新しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    ((failed++))
fi

# Test 5: delete_task_interactive
echo -n "Test 5: delete_task_interactive ... "
output=$(echo "" | delete_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #2 を削除しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    ((failed++))
fi

echo "========================================="
echo "Results: $passed passed, $failed failed"
echo "========================================="

# Cleanup
rm -f /tmp/test_funcs.sh "$TASKS_FILE" "$ORCHESTRATOR"

if [[ $failed -eq 0 ]]; then
    echo "✓ All tests PASSED"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
