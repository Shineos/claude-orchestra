#!/bin/bash
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

if ! command -v tput &> /dev/null; then
    tput() { :; }
fi

# Source only tui-core.sh
source "$CLAUDE_SCRIPTS_DIR/tui-core.sh"

echo "Testing tui_hline with pipefail..."
# Test with multi-byte char
tui_hline 10 "─"
echo "Success with multi-byte"

# Test with default
tui_hline 10
echo "Success with default"
