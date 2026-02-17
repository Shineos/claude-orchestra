#!/usr/bin/expect -f

set timeout 10
set project_dir "/Users/grace/dev/shineos/shineos-saas-starter"
log_file -a expect_debug.log

spawn bash "$project_dir/.claude/orchestra.sh" dashboard
expect "💠 CLAUDE ORCHESTRA"

# Tab to Active / Recent
send "\t"
sleep 1

# Try to match FAILED indicating we are on task #1
expect "FAILED"

# Press [C]
send "c"

# Expect the event log update
expect {
    "Completing task #1..." { puts "SUCCESS: TUI sent completion command." }
    timeout { puts "FAILURE: TUI did not react to \[C\]." }
}

# Wait for refresh
expect "Tasks refreshed."

# Exit
send "q"
expect eof

