#!/bin/bash
# Test runner script for Claude Orchestra acceptance tests

set -e

# Colors for output
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test directories
ACCEPTANCE_DIR="$SCRIPT_DIR/acceptance"

# Default options
VERBOSE=false
FILTER=""
REPORTER="terminal"  # terminal, junit

# Help function
show_help() {
    cat << EOF
${BLUE}Claude Orchestra Acceptance Test Runner${NC}

Usage: $0 [OPTIONS]

Options:
    -v, --verbose          Show verbose output
    -f, --filter PATTERN   Run tests matching pattern
    -r, --reporter TYPE    Output format (terminal, junit)
    -h, --help             Show this help message

Examples:
    $0                                    # Run all tests
    $0 -v                                 # Run with verbose output
    $0 -f orchestrator                    # Run only orchestrator tests
    $0 -f "add.*priority"                 # Run tests matching pattern

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -r|--reporter)
            REPORTER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Build bats command
BATS_CMD="bats -T"  # -T: Don't require terminal

if [[ "$VERBOSE" == "true" ]]; then
    BATS_CMD="$BATS_CMD --verbose"
    export BATS_VERBOSE=true
fi

if [[ -n "$FILTER" ]]; then
    BATS_CMD="$BATS_CMD --filter '$FILTER'"
fi

case "$REPORTER" in
    terminal)
        BATS_CMD="$BATS_CMD --formatter pretty"
        ;;
    junit)
        BATS_CMD="$BATS_CMD --formatter junit"
        ;;
esac

# Print header
echo ""
echo "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo "${BLUE}  Claude Orchestra Acceptance Tests${NC}"
echo "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "${YELLOW}Project:${NC} $PROJECT_ROOT"
echo "${YELLOW}Test directory:${NC} $ACCEPTANCE_DIR"
echo "${YELLOW}Verbose:${NC} $VERBOSE"
echo "${YELLOW}Filter:${NC} ${FILTER:-none}"
echo ""

# Check if bats is installed
if ! command -v bats &> /dev/null; then
    echo "${RED}Error: bats is not installed${NC}"
    echo ""
    echo "Install bats-core:"
    echo "  brew install bats-core"
    echo ""
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "${RED}Error: jq is not installed${NC}"
    echo ""
    echo "Install jq:"
    echo "  brew install jq"
    echo ""
    exit 1
fi

# Run tests
echo "${BLUE}Running tests...${NC}"
echo ""

# Set project root for tests
export PROJECT_ROOT="$PROJECT_ROOT"

# Set TERM for GitHub Actions environment
export TERM="${TERM:-xterm}"

# Find and run test files
TEST_FILES=$(find "$ACCEPTANCE_DIR" -name "*.bats" -type f | sort)

if [[ -z "$TEST_FILES" ]]; then
    echo "${YELLOW}No test files found in $ACCEPTANCE_DIR${NC}"
    exit 0
fi

# Count test files
TEST_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')
echo "${YELLOW}Found $TEST_COUNT test file(s)${NC}"
echo ""

# Run bats with the test files
eval "$BATS_CMD $TEST_FILES"
EXIT_CODE=$?

# Print summary
echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo "${GREEN}  All tests passed!${NC}"
    echo "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
else
    echo "${RED}═══════════════════════════════════════════════════════════════${NC}"
    echo "${RED}  Some tests failed${NC}"
    echo "${RED}═══════════════════════════════════════════════════════════════${NC}"
fi
echo ""

exit $EXIT_CODE
