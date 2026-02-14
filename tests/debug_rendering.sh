#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="$PROJECT_ROOT/.claude"

source "$CLAUDE_DIR/scripts/tui-core.sh"
source "$CLAUDE_DIR/scripts/tui-keyboard.sh"
source "$CLAUDE_DIR/scripts/tui-dialogs.sh"

# モック
TASKS_FILE="/tmp/debug_tasks.json"
echo '{"tasks": []}' > "$TASKS_FILE"

# tui_selection_dialog をテスト
test_selection() {
    local edit_opts="Description Agent Priority Notes"
    local target=$(tui_selection_dialog "Edit Property" "$edit_opts" 0 40 10)
    echo "Selected: $target"
}

# ターミナル初期化
stty -echo icanon
printf "\033[?25l"

test_selection

# 復元
stty echo icanon
printf "\033[?25h"
