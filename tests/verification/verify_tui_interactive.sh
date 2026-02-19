#!/bin/bash
# tests/verify_tui_interactive.sh
# Integration tests for TUI interactive functions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

# Mock environment
TASKS_FILE="/tmp/test_tasks_interactive.json"
echo '{"tasks":[{"id":1,"description":"Task 1","status":"pending"},{"id":2,"description":"Task 2","status":"pending"}]}' > "$TASKS_FILE"

get_terminal_height() { echo 24; }
get_terminal_width() { echo 80; }
tui_flush_input() { :; }
setup_terminal() { :; }
cleanup_terminal() { :; }
draw_dashboard() { :; }
show_message() { echo "MSG: $1"; }
tui_clear() { :; }
stty() { :; }
CLAUDE_DIR="/tmp"

# Mock orchestrator
ORCHESTRATOR="/tmp/mock_orch_interactive.sh"
cat > "$ORCHESTRATOR" << 'ORCHESTRATOR_EOF'
#!/bin/bash
case "$1" in
    start)
        # Update task to in_progress
        python3 -c "
import json
import sys
with open('$TASKS_FILE', 'r') as f:
    data = json.load(f)
for task in data['tasks']:
    if task['id'] == int('$2'):
        task['status'] = 'in_progress'
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "タスク #$2 を開始しました"
        ;;
    complete)
        python3 -c "
import json
with open('$TASKS_FILE', 'r') as f:
    data = json.load(f)
for task in data['tasks']:
    if task['id'] == int('$2'):
        task['status'] = 'done'
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "タスク #$2 を完了しました"
        ;;
    delete)
        python3 -c "
import json
with open('$TASKS_FILE', 'r') as f:
    data = json.load(f)
data['tasks'] = [t for t in data['tasks'] if t['id'] != int('$2')]
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "タスク #$2 を削除しました"
        ;;
    update)
        python3 -c "
import json
import sys
with open('$TASKS_FILE', 'r') as f:
    data = json.load(f)
for task in data['tasks']:
    if task['id'] == int('$2'):
        task['description'] = '$3'
with open('$TASKS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "タスク #$2 を更新しました"
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac
ORCHESTRATOR_EOF

chmod +x "$ORCHESTRATOR"

# Source the complete dashboard
source "$CLAUDE_SCRIPTS_DIR/dashboard.sh"

# Mock output to avoid terminal sequences
exec 2>/dev/null

echo "========================================="
echo "TUI Interactive Functions Tests"
echo "========================================="

passed=0
failed=0

# Test 1: get_all_task_ids
echo -n "Test 1: get_all_task_ids ... "
ids=$(get_all_task_ids)
if [[ "$ids" == "1 2" ]]; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL (got: $ids)"
    ((failed++))
fi

# Test 2: start_task_interactive via stdin input
echo -n "Test 2: start_task_interactive ... "
output=$(echo -e "\n" | start_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #1 を開始しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    echo "  Output: $output"
    ((failed++))
fi

# Test 3: complete_task_interactive
echo -n "Test 3: complete_task_interactive ... "
output=$(echo -e "\n" | complete_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #1 を完了しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    echo "  Output: $output"
    ((failed++))
fi

# Test 4: edit_task_interactive
echo -n "Test 4: edit_task_interactive ... "
output=$(echo -e "\nEdited Description\n" | edit_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #1 を更新しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    echo "  Output: $output"
    ((failed++))
fi

# Test 5: delete_task_interactive
echo -n "Test 5: delete_task_interactive ... "
output=$(echo -e "\n" | delete_task_interactive 2>&1 || true)
if echo "$output" | grep -q "タスク #2 を削除しました"; then
    echo "PASS"
    ((passed++))
else
    echo "FAIL"
    echo "  Output: $output"
    ((failed++))
fi

echo "========================================="
echo "Results: $passed passed, $failed failed"
echo "========================================="

# Cleanup
rm -f "$TASKS_FILE" "$ORCHESTRATOR"

if [[ $failed -eq 0 ]]; then
    echo "✓ All tests PASSED"
    exit 0
else
    echo "✗ Some tests FAILED"
    exit 1
fi
