#!/bin/bash
# tests/test_tui_core_functions.sh
# Test core TUI functions in tui-core.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

echo "========================================="
echo "TUI Core Functions Tests"
echo "========================================="

# Test 1: tui_clear function exists
echo -n "Test 1: tui_clear function exists ... "
if grep -q "^tui_clear()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 2: tui_save_cursor function exists
echo -n "Test 2: tui_save_cursor function exists ... "
if grep -q "^tui_save_cursor()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 3: tui_restore_cursor function exists
echo -n "Test 3: tui_restore_cursor function exists ... "
if grep -q "^tui_restore_cursor()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 4: tui_move function exists
echo -n "Test 4: tui_move function exists ... "
if grep -q "^tui_move()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 5: tui_hide_cursor function exists
echo -n "Test 5: tui_hide_cursor function exists ... "
if grep -q "^tui_hide_cursor()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 6: tui_show_cursor function exists
echo -n "Test 6: tui_show_cursor function exists ... "
if grep -q "^tui_show_cursor()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 7: tui_get_size function exists
echo -n "Test 7: tui_get_size function exists ... "
if grep -q "^tui_get_size()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 8: tui_hline function exists
echo -n "Test 8: tui_hline function exists ... "
if grep -q "^tui_hline()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 9: tui_vline function exists
echo -n "Test 9: tui_vline function exists ... "
if grep -q "^tui_vline()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 10: tui_box function exists
echo -n "Test 10: tui_box function exists ... "
if grep -q "^tui_box()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 11: tui_print function exists
echo -n "Test 11: tui_print function exists ... "
if grep -q "^tui_print()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 12: tui_get_status_color function exists
echo -n "Test 12: tui_get_status_color function exists ... "
if grep -q "^tui_get_status_color()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 13: tui_get_tasks function exists
echo -n "Test 13: tui_get_tasks function exists ... "
if grep -q "^tui_get_tasks()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 14: tui_get_stats function exists
echo -n "Test 14: tui_get_stats function exists ... "
if grep -q "^tui_get_stats()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 15: Verify tui_init_terminal function exists
echo -n "Test 15: tui_init_terminal function exists ... "
if grep -q "^tui_init_terminal()" "$CLAUDE_SCRIPTS_DIR/tui-core.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo "========================================="
echo "All 15 tests PASSED"
echo "========================================="
