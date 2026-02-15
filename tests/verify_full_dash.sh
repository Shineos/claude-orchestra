#!/usr/bin/expect -f

set timeout 30
set project_dir "/Users/grace/dev/shineos/shineos-saas-starter"

# Set environment to simplify testing (no AI, no auto-launch to avoid terminal sprawl)
set env(USE_AI) "false"
set env(ORCH_AUTO_CONFIRM) "yes"
set env(ORCH_NO_AUTO_LAUNCH) "yes"

# 1. Start with clean but valid tasks
exec echo "{\"tasks\": \[\], \"last_id\": 0}" > "$project_dir/.claude/tasks.json"

spawn bash "$project_dir/.claude/orchestra.sh" dashboard

# Verify Header and Layout
expect "CLAUDE ORCHESTRA"
expect "Pending Tasks"
expect "Active / Recent"
expect "(Command Mode)"

# 2. Test Add Task [A]
send "a"
expect "Task description..."
send "Verify Full Dash Flow\r"
expect "Adding task: Verify Full Dash Flow..."
expect "1 item"

# 3. Test ESC handling
send "a"
expect "Task description..."
send "Discarded"
send "\x1b" ;# ESC
expect "(Command Mode)"

# 4. Test Start Task [S] (on Pending Tab)
# Tab 0 is default
send "s"
expect "Starting task #1..."

# 5. Test Logs [L]
send "l"
expect "Live Logs Viewer"
expect "開始: \[#1\] Verify Full Dash Flow"
send "q" ;# Exit logs
expect "CLAUDE ORCHESTRA"

# 6. Test Complete Task [C] (Need to Tab to Active list)
send "\t" ;# Tab to Active / Recent
send "c"
expect "Completing task #1..."

# 7. Test Scan [R]
send "r"
expect "Scanning tasks..."

# 8. Test Exit [Q]
send "q"
expect eof

puts "\nVerification Success: All dashboard shortcuts and transitions verified."
