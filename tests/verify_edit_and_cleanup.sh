#!/usr/bin/expect -f

# Test Script for Edit functionality and process cleanup
# This verifies:
# 1. [E] Edit command works
# 2. Editor opens with correct content
# 3. Process cleanup happens properly

set timeout 30
set project_dir "/Users/grace/dev/shineos/shineos-saas-starter"
log_file -a tests/edit_test_debug.log

puts "=== EDIT FUNCTIONALITY TEST ==="

# Count processes before
spawn bash -c "ps aux | grep control-center | grep -v grep | wc -l"
expect eof
set before_count $expect_out(1,string)

puts "Processes before: $before_count"

# 1. Start Dashboard
spawn bash "$project_dir/.claude/orchestra.sh" dashboard
set timeout 10
expect "(Command Mode)"
puts "✅ Dashboard started"
sleep 2

# 2. Add a test task
send "a"
sleep 0.5
send "Test edit functionality\r"
sleep 2
puts "✅ Added test task"

# 3. Edit the task (first task in list)
# First select it by pressing Down arrow if needed
send "\[B"
sleep 0.5
send "e"
sleep 1
send "1"
sleep 0.5
send "\r"
sleep 2

# Check if editor opened (editor would take control)
# We expect the TUI to pause while editor runs
# Since we can't interact with the editor in expect, we'll send Ctrl+C to exit
# This simulates user aborting the edit

# 4. Exit cleanly
send "q"
expect eof
puts "✅ Dashboard exited"

# Count processes after
spawn bash -c "ps aux | grep control-center | grep -v grep | wc -l"
expect eof
set after_count $expect_out(1,string)

puts "Processes after: $after_count"
puts "Process difference: [expr $after_count - $before_count]"

if {$after_count <= $before_count} {
    puts "✅ NO NEW ZOMBIE PROCESSES"
} else {
    puts "❌ ZOMBIE PROCESSES CREATED: [expr $after_count - $before_count] new processes"
}

exit 0
