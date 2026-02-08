# Bats helper functions for Claude Orchestra acceptance tests
# Source this file in your test files: load 'helpers/bats_helper'

# Project root directory
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)}"

# Claude directory
CLAUDE_DIR="$PROJECT_ROOT/.claude"

# Orchestrator script
ORCHESTRATOR="$CLAUDE_DIR/scripts/orchestrator.sh"

# Agent script
AGENT="$CLAUDE_DIR/agent.sh"

# Tasks file
TASKS_FILE="$CLAUDE_DIR/tasks.json"

# PIDs directory
PIDS_DIR="$CLAUDE_DIR/pids"

# Setup function - runs before each test
setup() {
    # Create a backup of existing tasks.json if it exists
    if [[ -f "$TASKS_FILE" ]]; then
        cp "$TASKS_FILE" "$TASKS_FILE.bak"
    fi

    # Create a backup of existing approvals.json if it exists
    if [[ -f "$APPROVALS_FILE" ]]; then
        cp "$APPROVALS_FILE" "$APPROVALS_FILE.bak"
    fi

    # Kill any running agents before test
    kill_running_agents
}

# Teardown function - runs after each test
teardown() {
    # Restore original tasks.json
    if [[ -f "$TASKS_FILE.bak" ]]; then
        mv "$TASKS_FILE.bak" "$TASKS_FILE"
    fi

    # Restore original approvals.json
    if [[ -f "$APPROVALS_FILE.bak" ]]; then
        mv "$APPROVALS_FILE.bak" "$APPROVALS_FILE"
    fi

    # Kill any running agents after test
    kill_running_agents

    # Clean up test worktrees
    cleanup_test_worktrees
}

# Kill all running agents
kill_running_agents() {
    local agents=("frontend" "backend" "tests" "docs")
    for agent in "${agents[@]}"; do
        local pid_file="$PIDS_DIR/$agent.json"
        if [[ -f "$pid_file" ]]; then
            local pid=$(jq -r '.pid' "$pid_file" 2>/dev/null || echo "")
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                wait "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file" 2>/dev/null || true
        fi
    done
}

# Clean up test worktrees
cleanup_test_worktrees() {
    local worktrees_dir="$PROJECT_ROOT/.claude/worktrees"
    if [[ -d "$worktrees_dir" ]]; then
        # Remove worktrees that start with "test-"
        find "$worktrees_dir" -maxdepth 1 -type d -name "test-*" -exec rm -rf {} \; 2>/dev/null || true
    fi
}

# Initialize or reset tasks.json
init_empty_tasks() {
    cat > "$TASKS_FILE" <<EOF
{
  "tasks": [],
  "next_id": 1,
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Add a task via orchestrator
add_task() {
    local task="$1"
    local agent="${2:-}"
    local priority="${3:-normal}"
    local deps="${4:-}"

    run bash "$ORCHESTRATOR" add "$task" ${agent:+$agent} ${priority:+$priority} ${deps:+$deps}
}

# Get task count
task_count() {
    jq '.tasks | length' "$TASKS_FILE"
}

# Get task by ID
get_task() {
    local task_id="$1"
    jq ".tasks[] | select(.id == $task_id)" "$TASKS_FILE"
}

# Get task status
get_task_status() {
    local task_id="$1"
    jq -r ".tasks[] | select(.id == $task_id) | .status" "$TASKS_FILE"
}

# Wait for task status to change
wait_for_status() {
    local task_id="$1"
    local expected_status="$2"
    local timeout="${3:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local status=$(get_task_status "$task_id")
        if [[ "$status" == "$expected_status" ]]; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

# Assert task exists
assert_task_exists() {
    local task_id="$1"
    local result=$(get_task "$task_id")
    if [[ "$result" != *"\"id\": $task_id"* ]]; then
        echo "Expected task to contain \"id\": $task_id"
        echo "Got: $result"
        return 1
    fi
}

# Assert task has status
assert_task_status() {
    local task_id="$1"
    local expected_status="$2"
    local actual_status=$(get_task_status "$task_id")
    assert_equal "$actual_status" "$expected_status"
}

# Assert agent is running
assert_agent_running() {
    local agent="$1"
    local pid_file="$PIDS_DIR/$agent.json"

    [[ -f "$pid_file" ]]
    local pid=$(jq -r '.pid' "$pid_file")
    kill -0 "$pid" 2>/dev/null
}

# Assert agent is not running
assert_agent_not_running() {
    local agent="$1"
    local pid_file="$PIDS_DIR/$agent.json"

    if [[ -f "$pid_file" ]]; then
        local pid=$(jq -r '.pid' "$pid_file")
        if [[ -n "$pid" ]]; then
            ! kill -0 "$pid" 2>/dev/null
        fi
    fi
}

# Create a test fixture task
create_fixture_task() {
    local description="$1"
    local agent="${2:-frontend}"
    local priority="${3:-normal}"
    local status="${4:-pending}"

    local task_id=$(jq '.next_id' "$TASKS_FILE")
    local next_id=$((task_id + 1))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Add task to tasks array
    jq --arg desc "$description" \
       --arg agent "$agent" \
       --arg priority "$priority" \
       --arg status "$status" \
       --arg id "$task_id" \
       --arg created "$timestamp" \
       '.tasks += [{
         id: ($id | tonumber),
         description: $desc,
         agent: $agent,
         priority: $priority,
         status: $status,
         created_at: $created,
         dependencies: []
       }] | .next_id = ($next_id | tonumber)' \
       "$TASKS_FILE" > "$TASKS_FILE.tmp"

    mv "$TASKS_FILE.tmp" "$TASKS_FILE"
    echo "$task_id"
}

# =============================================================================
# Approval system helper functions
# ==============================================================================

# Approvals file
APPROVALS_FILE="$CLAUDE_DIR/approvals.json"

# Initialize or reset approvals.json
init_empty_approvals() {
    cat > "$APPROVALS_FILE" <<EOF
{
  "approvals": [],
  "last_id": 0
}
EOF
}

# Get approval count
approval_count() {
    jq '.approvals | length' "$APPROVALS_FILE"
}

# Get approval by ID
get_approval() {
    local approval_id="$1"
    jq ".approvals[] | select(.id == $approval_id)" "$APPROVALS_FILE"
}

# Get approval status
get_approval_status() {
    local approval_id="$1"
    jq -r ".approvals[] | select(.id == $approval_id) | .status" "$APPROVALS_FILE"
}

# Create a test fixture approval
create_fixture_approval() {
    local task_id="$1"
    local operation_type="${2:-test_operation}"
    local details_json="${3}"
    local status="${4:-pending}"

    # Default details_json if empty
    if [[ -z "$details_json" ]]; then
        details_json='{"test":"data"}'
    fi

    # Generate approval ID (same logic as generate_approval_id in approval.sh)
    local last_id=$(jq -r '.last_id' "$APPROVALS_FILE" 2>/dev/null || echo "0")
    local approval_id=$((last_id + 1))
    local next_id=$((approval_id + 1))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Add approval to approvals array
    # Note: Using --arg for details and parsing with fromjson
    jq --arg tid "$task_id" \
       --arg op "$operation_type" \
       --arg details "$details_json" \
       --arg status "$status" \
       --arg id "$approval_id" \
       --arg next_id "$next_id" \
       --arg created "$timestamp" \
       '.approvals += [{
         id: ($id | tonumber),
         task_id: $tid,
         operation_type: $op,
         details: (if $details == "" then {} else ($details | fromjson) end),
         requested_at: $created,
         requested_by: "test-user",
         status: $status,
         response: null
       }] | .last_id = ($next_id | tonumber)' \
       "$APPROVALS_FILE" > "$APPROVALS_FILE.tmp"

    mv "$APPROVALS_FILE.tmp" "$APPROVALS_FILE"
    echo "$approval_id"
}

# Assert approval exists
assert_approval_exists() {
    local approval_id="$1"
    local result=$(get_approval "$approval_id")
    if [[ "$result" != *"\"id\": $approval_id"* ]]; then
        echo "Expected approval to contain \"id\": $approval_id"
        echo "Got: $result"
        return 1
    fi
}

# Assert approval has status
assert_approval_status() {
    local approval_id="$1"
    local expected_status="$2"
    local actual_status=$(get_approval_status "$approval_id")
    assert_equal "$expected_status" "$actual_status"
}

# Assert approval exists with given task_id
assert_approval_for_task() {
    local approval_id="$1"
    local expected_task_id="$2"
    local approval=$(get_approval "$approval_id")
    echo "$approval" | grep -q "\"task_id\": \"$expected_task_id\""
}

# =============================================================================
# Bats assertion helpers (since Bats 1.x doesn't have built-in asserts)
# ==============================================================================

# Assert that the last command succeeded
assert_success() {
    if [[ "$status" -ne 0 ]]; then
        echo "Command failed with exit status $status"
        echo "Output: $output"
        return 1
    fi
}

# Assert that the last command failed
assert_failure() {
    if [[ "$status" -eq 0 ]]; then
        echo "Command succeeded but should have failed"
        echo "Output: $output"
        return 1
    fi
}

# Assert that two values are equal
assert_equal() {
    local expected="$1"
    local actual="$2"
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected: '$expected'"
        echo "Actual:   '$actual'"
        return 1
    fi
}

# Assert that output contains a substring
assert_output() {
    local expected="$1"
    if [[ ! "$output" =~ $expected ]]; then
        echo "Expected output to contain: '$expected'"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert that output contains partial substring
assert_output_partial() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: '$expected'"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert that output does not contain a substring
refute_output() {
    local unexpected="$1"
    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output NOT to contain: '$unexpected'"
        echo "Actual output: $output"
        return 1
    fi
}

# Assert that a condition is true
assert() {
    if [[ ! "$@" ]]; then
        echo "Assertion failed: $*"
        return 1
    fi
}

# Print debug info (only when tests fail or verbose mode)
debug_info() {
    if [[ "${BATS_VERBOSE}" == "true" ]] || [[ "${BATS_CWD}" ]]; then
        echo "=== DEBUG INFO ==="
        echo "Tasks file:"
        cat "$TASKS_FILE" 2>/dev/null || echo "No tasks file"
        echo ""
        echo "Approvals file:"
        cat "$APPROVALS_FILE" 2>/dev/null || echo "No approvals file"
        echo "=================="
    fi
}
