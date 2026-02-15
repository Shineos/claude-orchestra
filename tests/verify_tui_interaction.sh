#!/usr/bin/expect -f

set timeout 20
set project_dir "/Users/grace/dev/shineos/shineos-saas-starter"

# Set environment to bypass AI and auto-confirm
set env(USE_AI) "false"
set env(ORCH_AUTO_CONFIRM) "yes"
set env(ORCH_NO_AUTO_LAUNCH) "yes"

# Ensure clean state (manually since init is flaky in tests)
exec rm -f "$project_dir/.claude/tasks.json"
# Add a base task for testing
exec bash "$project_dir/.claude/orchestra.sh" add "Initial Task"

# Start dashboard
# We use -no-color or similar if possible? No, we want to test color.
# Bubbletea handles TERM=xterm-256color well.
spawn bash "$project_dir/.claude/orchestra.sh" dashboard
expect "CONTROL CENTER v2.0"

# --- Test Case 1: Add Task ---
send "a"
expect "Task description..."
send "Manual Test Task\r"
# Should return to command mode and show event
expect "Adding task: Manual Test Task..."
expect "(Command Mode)"

# --- Test Case 2: ESC in Input Mode ---
send "a"
expect "Task description..."
send "This should be canceled"
send "\x1b" ;# Escape key
# Should return to command mode WITHOUT quitting
expect "(Command Mode)"

# --- Test Case 3: Start Task ---
# Wait for task list to refresh
sleep 2
send "s"
expect "Starting task #1..."

# --- Test Case 4: Quit ---
send "q"
expect eof

puts "\nVerification finished successfully!"
