#!/bin/bash
# Remove strict modes to allow debugging and to simulate user environment which might not have them
# set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SCRIPTS_DIR="$SCRIPT_DIR/../.claude/scripts"

# Ensure tput exists or mock it
if ! command -v tput &> /dev/null; then
    tput() { :; }
fi

# Function to check if we are running in a compatible shell
echo "Bash version: $BASH_VERSION"

# Source libraries
echo "Sourcing tui-core.sh..."
source "$CLAUDE_SCRIPTS_DIR/tui-core.sh" || echo "Failed to source tui-core.sh"
echo "Sourcing tui-keyboard.sh..."
source "$CLAUDE_SCRIPTS_DIR/tui-keyboard.sh" || echo "Failed to source tui-keyboard.sh"
echo "Sourcing tui-renderer.sh..."
source "$CLAUDE_SCRIPTS_DIR/tui-renderer.sh" || echo "Failed to source tui-renderer.sh"
echo "Sourcing tui-dialogs.sh..."
source "$CLAUDE_SCRIPTS_DIR/tui-dialogs.sh" || echo "Failed to source tui-dialogs.sh"

# Mock terminal size
tui_get_rows() { echo 30; }
tui_get_cols() { echo 100; }
TUI_TERMINAL_INITIALIZED=true

echo "Starting tui_selection_dialog..."
# We need to simulate input or run in a way that doesn't hang.
# tui_selection_dialog waits for input.
# We can pipe input to it?
# But it reads from /dev/tty or similar if configured?
# tui-keyboard.sh uses `IFS= read -rsn1 -t "$timeout" char` from stdin (implied).

echo "q" | tui_selection_dialog "Select Agent" "Auto(AI) frontend backend tests docs planner architect coder reviewer tester" 0 60 12
EXIT_CODE=$?

echo "tui_selection_dialog returned: $EXIT_CODE"

if [[ -f /tmp/claude_dashboard_debug.log ]]; then
    echo "--- Debug Log ---"
    cat /tmp/claude_dashboard_debug.log
fi

echo "Finished verification."
