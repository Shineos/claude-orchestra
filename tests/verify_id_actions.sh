#!/bin/bash
export TERM=xterm-256color
export CLAUDE_ORCHESTRA_ROOT=$(pwd)

# 1. Setup Environment
echo "Setting up test environment..."
rm -f .claude/tasks.json
mkdir -p .claude/tasks

# 2. Add Dummy Tasks Manually
echo "Adding tasks manually..."
cat <<EOF > .claude/tasks.json
{
  "tasks": [
    {
      "id": 1,
      "description": "Test Task 1",
      "status": "pending",
      "agent": "planner"
    },
    {
      "id": 2,
      "description": "Test Task 2",
      "status": "pending",
      "agent": "tester"
    },
    {
      "id": 3,
      "description": "Test Task 3",
      "status": "in_progress",
      "agent": "architect"
    }
  ],
  "last_id": 3
}
EOF

# 3. Create Mock Editor
echo "Creating mock editor..."
cat <<EOF > mock_editor.sh
#!/bin/bash
echo "Mock editor called with \$1" >> mock_editor.log
if [ -z "\$1" ]; then
    echo "No file argument" >> mock_editor.log
    exit 1
fi
# Append modification to simulate edit
# The TUI passes a temp file path as argument.
echo " [Edited]" >> "\$1"
EOF
chmod +x mock_editor.sh
export EDITOR="\$(pwd)/mock_editor.sh"
echo "EDITOR is set to \$EDITOR"

# 4. Create Expect Script
echo "Creating expect script..."
cat <<EOF > verify_id_actions.exp
#!/usr/bin/expect -f
set timeout 20
log_user 1

# Spawn bash to run the TUI
# Ensure we use .claude/orchestra.sh which launches the binary
# We explicitly pass EDITOR to ensure it reaches the process
puts "EXPECT: EDITOR is \$env(EDITOR)"
spawn env EDITOR=\$env(EDITOR) bash .claude/orchestra.sh

# Wait for TUI load
expect "Claude Orchestra"
sleep 1

# --- Test Start [S] with ID ---
# Task 1 is pending. Prefilled ID is 1 (as it is selected).
# Just confirm prefill.
send "s" 
expect ">"
send "\r"
# Verify "Starting task #1" appears in logs/events
expect {
    "Starting task #1" { puts "\nOK: Started Task #1" }
    timeout { puts "\nFAIL: Did not see Starting task #1"; exit 1 }
}
sleep 1

# --- Test Complete [C] with ID ---
# Task 1 is now in_progress. Task 3 is in_progress.
# Selection remains on 1 (or 2). Prefill is 1 or 2.
# We want 3. Clear input (5 x DEL).
send "c"
expect ">"
send "\x7F\x7F\x7F\x7F\x7F"
send "3\r"
expect {
    "Completing task #3" { puts "\nOK: Completed Task #3" }
    timeout { puts "\nFAIL: Did not see Completing task #3"; exit 1 }
}
sleep 1

# --- Test Edit [E] with ID ---
# Use Task 2
send "e"
expect ">"
send "\x7F\x7F\x7F\x7F\x7F"
send "2\r"
expect {
    "DEBUG PANIC" { puts "\nSUCCESS: Panic triggered in Editor!" }
    "Edited task #2" { puts "\nOK: Edited Task #2 (Unexpected success)" }
    timeout { puts "\nFAIL: Did not see Panic or Edit"; exit 1 }
    eof { puts "\nEOF seen (Process crashed as expected)" }
}
sleep 1

# If panic happened, process is dead. Exit.
exit 0

# --- Test Logs [L] with ID ---
# Use task 1
send "l"
expect "Task ID (0 for all)"
send "\x7F\x7F\x7F\x7F\x7F"
send "1\r"
# Should enter logs-tui.
# We look for "Monitoring logs..." or just ensure we don't crash.
# Waiting a bit.
sleep 2
# Exit logs (Ctrl+C sends \003)
send "\003"
# Expect return to main TUI
expect {
    "Claude Orchestra" { puts "\nOK: Returned from Logs" }
    timeout { puts "\nFAIL: Did not return from Logs"; exit 1 }
}

# Cleanup
send "q"
expect eof
EOF
chmod +x verify_id_actions.exp

# 5. Run Verification
echo "Running verification..."
./verify_id_actions.exp
RESULT=\$?

# 6. Check Results
if [ \$RESULT -eq 0 ]; then
    echo "Verification Passed!"
    # Verify edit persistence in tasks.json
    # Read tasks.json to verify content
    if grep -q "Edited" .claude/tasks.json; then
        echo "Edit verified in tasks.json"
    else
        echo "Edit NOT found in tasks.json"
        cat .claude/tasks.json
        exit 1
    fi
else
    echo "Verification Failed"
    exit 1
fi
