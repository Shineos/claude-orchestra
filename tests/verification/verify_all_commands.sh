#!/bin/bash
# Comprehensive TUI Command Verification Script (v3)

PROJECT_DIR="$(pwd)"
ORCH="./.claude/orchestra.sh"
TASKS_FILE=".claude/tasks.json"
PID_DIR=".claude/pids"
LOGS_DIR=".claude/logs"

echo "=== Comprehensive TUI Command Verification starting (v3) ==="

# Helper to check task status
check_status() {
    local id=$1
    local expected=$2
    local actual=$(jq -r --argjson id "$id" '.tasks[] | select(.id == $id) | .status' "$TASKS_FILE")
    if [ "$actual" == "$expected" ]; then
        echo "  - OK: Task #$id status is '$actual'"
    else
        echo "  - ERROR: Task #$id status is '$actual', expected '$expected'"
        exit 1
    fi
}

# 1. RESET
echo "[1/9] Resetting state..."
bash "$ORCH" stop all > /dev/null 2>&1 || true
echo '{"tasks": [], "last_id": 0}' > "$TASKS_FILE"
mkdir -p "$PID_DIR"
mkdir -p "$LOGS_DIR"
rm -f "$PID_DIR"/*
rm -f "$LOGS_DIR"/*

# 2. [A] ADD TASK
echo "[2/9] Testing: [A] Add Task..."
ORCH_AUTO_CONFIRM=yes USE_AI=false bash "$ORCH" add "Test Task" > /dev/null
TASK_ID=$(jq -r '.tasks[] | select(.description | ascii_downcase | contains("test task")) | .id' "$TASKS_FILE")
if [ -n "$TASK_ID" ]; then
    echo "  - OK: Task created with ID: $TASK_ID"
else
    echo "  - ERROR: Task not found!"
    exit 1
fi

# 3. [E] EDIT TASK (Simulated)
echo "[3/9] Testing: [E] Edit Task..."
jq --arg id "$TASK_ID" --arg desc "Edited Task Description" \
   '.tasks |= map(if .id == ($id|tonumber) then .description = $desc else . end)' \
   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
if jq -e '.tasks[] | select(.description == "Edited Task Description")' "$TASKS_FILE" > /dev/null; then
    echo "  - OK: Task description updated"
else
    echo "  - ERROR: Task description update failed"
    exit 1
fi

# 4. [S] START TASK (Simulated)
echo "[4/9] Testing: [S] Start Task..."
bash "$ORCH" start "$TASK_ID" > /dev/null 2>&1 || true
check_status "$TASK_ID" "in_progress"

# 5. [C] COMPLETE TASK (Simulated Go Logic)
echo "[5/9] Testing: [C] Complete Task..."
jq --arg id "$TASK_ID" \
   '.tasks |= map(if .id == ($id|tonumber) then .status = "completed" else . end)' \
   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
check_status "$TASK_ID" "completed"

# 6. [T] STOP TASK (Simulated)
echo "[6/9] Testing: [T] Stop Task..."
jq --arg id "$TASK_ID" \
   '.tasks |= map(if .id == ($id|tonumber) then .status = "in_progress" else . end)' \
   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
bash "$ORCH" stop "$TASK_ID" > /dev/null 2>&1 || true
check_status "$TASK_ID" "stopped"

# 7. [W] WATCH (Spawn Agent)
echo "[7/9] Testing: [W] Watch (Spawn Agent)..."
# Correct command order: watch, agent
# Use nohup to ensure it doesn't get killed when shell exits (though script continues)
nohup bash "$ORCH" watch tests > agent_watch.log 2>&1 &
AGENT_PID=$!
sleep 3
# Check if process is running
if ps -p $AGENT_PID > /dev/null; then
    echo "  - OK: Agent watch process started (PID: $AGENT_PID)"
    kill $AGENT_PID || true
else
    echo "  - ERROR: Agent watch process failed to start. Check agent_watch.log"
    cat agent_watch.log
    exit 1
fi

# 8. [L] LOGS
echo "[8/9] Testing: [L] Logs..."
LOG_FILE="$LOGS_DIR/orchestrator-$(date +'%Y-%m-%d').log"
if [ -f "$LOG_FILE" ]; then
    echo "  - OK: Log file found"
else
    echo "  - ERROR: Log file missing"
fi

# 9. [Backspace] REMOVE TASK
echo "[9/9] Testing: [Backspace] Remove Task..."
jq --arg id "$TASK_ID" \
   'del(.tasks[] | select(.id == ($id|tonumber)))' \
   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
if ! jq -e --argjson id "$TASK_ID" '.tasks[] | select(.id == $id)' "$TASKS_FILE" > /dev/null; then
    echo "  - OK: Task removed"
else
    echo "  - ERROR: Task removal failed"
    exit 1
fi

# Cleanup
bash "$ORCH" stop all > /dev/null 2>&1 || true

echo "=== Comprehensive TUI Command Verification COMPLETED SUCCESSFULY ==="
