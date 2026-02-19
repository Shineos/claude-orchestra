#!/bin/bash
# tests/verify_tui_simple.sh
# Simplified tests that verify core functionality without full interaction

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

echo "========================================="
echo "TUI Simple Function Tests"
echo "========================================="

# Test 1: get_all_task_ids function extraction
echo -n "Test 1: get_all_task_ids function exists ... "
if grep -q "^get_all_task_ids()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 2: prompt_edit_bottom function exists
echo -n "Test 2: prompt_edit_bottom function exists ... "
if grep -q "^prompt_edit_bottom()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 3: prompt_select_horizontal function exists
echo -n "Test 3: prompt_select_horizontal function exists ... "
if grep -q "^prompt_select_horizontal()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 4: start_task_interactive function exists
echo -n "Test 4: start_task_interactive function exists ... "
if grep -q "^start_task_interactive()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 5: edit_task_interactive function exists
echo -n "Test 5: edit_task_interactive function exists ... "
if grep -q "^edit_task_interactive()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 6: delete_task_interactive function exists
echo -n "Test 6: delete_task_interactive function exists ... "
if grep -q "^delete_task_interactive()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 7: complete_task_interactive function exists
echo -n "Test 7: complete_task_interactive function exists ... "
if grep -q "^complete_task_interactive()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 8: Verify functions are called correctly
echo -n "Test 8: start_task_interactive calls get_all_task_ids ... "
if grep -A20 "^start_task_interactive()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh" | grep -q "get_all_task_ids"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 9: Verify prompt_input calls prompt_edit_bottom
echo -n "Test 9: prompt_input calls prompt_edit_bottom ... "
if grep -A5 "^prompt_input()" "$CLAUDE_SCRIPTS_DIR/dashboard.sh" | grep -q "prompt_edit_bottom"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 10: Verify orchestrator integration
echo -n "Test 10: Functions use ORCHESTRATOR variable ... "
if grep -q 'ORCHESTRATOR' "$CLAUDE_SCRIPTS_DIR/dashboard.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo "========================================="
echo "All 10 tests PASSED"
echo "========================================="
