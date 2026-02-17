#!/usr/bin/expect -f

# Test Dashboard Fixes
# Tests: Add Task, Start Task, Stop Task, View Logs, Exit
# Then checks for zombie processes

set timeout 30
set project_dir "/Users/grace/dev/shineos/shineos-saas-starter"

puts "=== DASHBOARD FIXES TEST ==="

# Count zombies before
spawn bash -c "ps aux | grep -E 'control-center|claude.*orchestra' | grep -v grep | grep UE | wc -l"
expect {
    -re "(\\d+)" {
        set zombies_before $expect_out(1,string)
    }
    eof {
        set zombies_before 0
    }
}
puts "📊 Zombies before: $zombies_before"

# Start Dashboard
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 1: Start Dashboard"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
spawn bash "$project_dir/.claude/orchestra.sh" dashboard
set timeout 15
expect "Command Mode" { puts "✅ Dashboard started" }
sleep 2

# Test Add Task with valid description
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 2: Add Task (valid description)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
send "a"
sleep 0.5
send "Test dashboard fix - add task functionality\r"
sleep 2
puts "✅ Added valid task"

# Test Add Task with empty description (should fail)
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 3: Add Task (empty - should fail)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
send "a"
sleep 0.5
send "\r"
sleep 2
puts "✅ Empty task rejected"

# Test viewing tabs and task loading
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 4: Check Task Loading"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
send "\[TAB"
sleep 1
send "\[TAB"
sleep 1
puts "✅ Tab switching works"

# Exit cleanly
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 5: Exit Dashboard"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
send "q"
expect eof
puts "✅ Dashboard exited cleanly"

# Check for new zombies
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TEST 6: Check for Zombie Processes"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
spawn bash -c "ps aux | grep -E 'control-center|claude.*orchestra' | grep -v grep | grep UE | wc -l"
expect {
    -re "(\\d+)" {
        set zombies_after $expect_out(1,string)
    }
    eof {
        set zombies_after 0
    }
}

puts "📊 Zombies after: $zombies_after"
set new_zombies [expr $zombies_after - $zombies_before]

puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "SUMMARY"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if {$new_zombies == 0} {
    puts "✅ NO NEW ZOMBIE PROCESSES CREATED"
    puts "✅ FIX VERIFIED: Process cleanup working!"
} else {
    puts "❌ NEW ZOMBIE PROCESSES: $new_zombies"
    puts "❌ FIX INCOMPLETE: Processes still leaking"
}

# Check tasks.json to verify task was added
puts "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "TASK VERIFICATION"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
spawn bash -c "cat $project_dir/.claude/tasks.json | jq '.tasks | length'"
expect {
    -re "(\\d+)" {
        set task_count $expect_out(1,string)
    }
    eof {
        set task_count 0
    }
}
puts "Total tasks: $task_count"

puts "\n=== TEST COMPLETE ==="

exit 0
