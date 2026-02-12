# Bats helper functions for Claude Orchestra acceptance tests
# Source this file in your test files: load 'helpers/bats_helper'

# Project root directory
# BATS_TEST_FILENAME points to the test file (e.g., /path/to/tests/acceptance/test.bats)
# We need to go up 2 levels from tests/acceptance to reach project root
if [[ -n "${BATS_TEST_FILENAME}" ]]; then
    # BATS_TEST_FILENAME is like: /path/to/tests/acceptance/test.bats
    # dirname gives: /path/to/tests/acceptance
    # We need to go up 2 levels: acceptance -> tests -> project_root
    TEST_DIR="$(dirname "${BATS_TEST_FILENAME}")"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${TEST_DIR}/.." && pwd)}"
else
    # Fallback when running outside of BATS
    # BASH_SOURCE[0] is this file: /path/to/tests/helpers/bats_helper.bash
    # dirname gives: /path/to/tests/helpers
    # Go up 2 levels to reach project root
    HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${HELPER_DIR}/../.." && pwd)}"
fi

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
                # Note: Removed wait "$pid" to avoid hanging in test environment
                # Process will be reaped by the system
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
  "last_id": 0
}
EOF
}

# Add a task via orchestrator
# Returns the output of the command
add_task() {
    local task="$1"
    local agent="${2:-}"
    local priority="${3:-normal}"
    local deps="${4:-}"

    bash "$ORCHESTRATOR" add "$task" ${agent:+$agent} ${priority:+$priority} ${deps:+$deps}
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
# Arguments: agent_name [max_wait_seconds]
assert_agent_running() {
    local agent="$1"
    local max_wait="${2:-10}"
    local pid_file="$PIDS_DIR/${agent}.json"
    local pid_text_file="$PIDS_DIR/${agent}.pid"
    local elapsed=0

    # Wait for agent to start (with timeout)
    while [[ $elapsed -lt $max_wait ]]; do
        # Check for either .json or .pid file (orchestrator writes .pid, tests may create .json)
        local pid=""
        local found_file=""

        if [[ -f "$pid_file" ]]; then
            pid=$(jq -r '.pid' "$pid_file" 2>/dev/null || echo "")
            found_file="(json)"
        elif [[ -f "$pid_text_file" ]]; then
            pid=$(cat "$pid_text_file" 2>/dev/null || echo "")
            found_file="(pid)"
        fi

        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi

        # If neither file type exists, definitely wait
        if [[ -z "$found_file" ]]; then
            sleep 1
        fi
        ((elapsed++))
    done

    # Final check after timeout (check both file types)
    local pid=""
    if [[ -f "$pid_file" ]]; then
        pid=$(jq -r '.pid' "$pid_file" 2>/dev/null || echo "")
    elif [[ -f "$pid_text_file" ]]; then
        pid=$(cat "$pid_text_file" 2>/dev/null || echo "")
    fi

    if [[ -n "$pid" ]]; then
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            echo "Agent $agent PID file exists but process not running (PID: $pid)"
            return 1
        fi
    fi

    echo "Agent $agent not running after ${max_wait}s (neither .json nor .pid file found)"
    return 1
}

# Assert agent is not running
assert_agent_not_running() {
    local agent="$1"
    local pid_file="$PIDS_DIR/${agent}.json"
    local pid_text_file="$PIDS_DIR/${agent}.pid"

    # Check both .json and .pid files
    local json_running=false
    local pid_running=false

    if [[ -f "$pid_file" ]]; then
        local pid=$(jq -r '.pid' "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            json_running=true
        fi
    fi

    if [[ -f "$pid_text_file" ]]; then
        local pid=$(cat "$pid_text_file" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            pid_running=true
        fi
    fi

    # Agent is considered running if EITHER file exists with valid PID
    if [[ "$json_running" == "true" ]] || [[ "$pid_running" == "true" ]]; then
        return 1
    else
        return 0
    fi
}

# Create a test fixture task
create_fixture_task() {
    local description="$1"
    local agent="${2:-frontend}"
    local priority="${3:-normal}"
    local status="${4:-pending}"

    local last_id=$(jq '.last_id' "$TASKS_FILE")
    local task_id=$((last_id + 1))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Add task to tasks array
    jq --arg desc "$description" \
       --arg agent "$agent" \
       --arg priority "$priority" \
       --arg status "$status" \
       --argjson id "$task_id" \
       --arg created "$timestamp" \
       '.tasks += [{
         id: $id,
         description: $desc,
         agent: $agent,
         priority: $priority,
         status: $status,
         created_at: $created,
         updated_at: $created,
         dependencies: []
       }] | .last_id = $id' \
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
       --argjson id "$approval_id" \
       --arg created "$timestamp" \
       '.approvals += [{
         id: $id,
         task_id: $tid,
         operation_type: $op,
         details: (if $details == "" then {} else ($details | fromjson) end),
         requested_at: $created,
         requested_by: "test-user",
         status: $status,
         response: null
       }] | .last_id = $id' \
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
# Supports --partial flag for partial substring match
assert_output() {
    local expected=""
    local use_partial=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --partial)
                use_partial=true
                shift
                ;;
            *)
                expected="$1"
                shift
                ;;
        esac
    done

    if [[ "$use_partial" == "true" ]]; then
        # Partial substring match
        if [[ "$output" != *"$expected"* ]]; then
            echo "Expected output to contain: '$expected'"
            echo "Actual output: $output"
            return 1
        fi
    else
        # Regex match
        if [[ ! "$output" =~ $expected ]]; then
            echo "Expected output to match: '$expected'"
            echo "Actual output: $output"
            return 1
        fi
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
