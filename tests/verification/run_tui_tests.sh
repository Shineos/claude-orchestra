#!/bin/bash
# tests/run_tui_tests.sh
# Master test suite for TUI functions

# Don't use set -e here, we want to catch failures manually
# set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        TUI Functions Test Suite                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

total_passed=0
total_failed=0

run_test_suite() {
    local suite_name="$1"
    local suite_file="$2"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $suite_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if bash "$suite_file" 2>&1; then
        echo "✓ $suite_name: PASSED"
        ((total_passed++))
    else
        local exit_code=$?
        echo "✗ $suite_name: FAILED (exit code: $exit_code)"
        ((total_failed++))
    fi
    echo ""
}

# Run all test suites
run_test_suite "Function Existence Tests" "$SCRIPT_DIR/verify_tui_simple.sh"
run_test_suite "Unit Tests" "$SCRIPT_DIR/verify_tui_functions.sh"
run_test_suite "TUI Core Functions Tests" "$SCRIPT_DIR/test_tui_core_functions.sh"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   Test Summary                             ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Total Suites Passed: $total_passed                                   ║"
echo "║  Total Suites Failed: $total_failed                                   ║"
echo "╚════════════════════════════════════════════════════════════╝"

if [[ $total_failed -eq 0 ]]; then
    echo "✓ All test suites PASSED"
    exit 0
else
    echo "✗ Some test suites FAILED"
    exit 1
fi
