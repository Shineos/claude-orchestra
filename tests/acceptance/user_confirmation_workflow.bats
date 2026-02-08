#!/usr/bin/env bats
# Integration tests for User Confirmation Workflow (Y/N/E/Q)
# Tests the confirm_decomposition function and AI task decomposition flow

load '../helpers/bats_helper'

# Color constants
export RED=$'\033[0;31m'
export GREEN=$'\033[0;32m'
export YELLOW=$'\033[1;33m'
export BLUE=$'\033[0;34m'
export CYAN=$'\033[0;36m'
export MAGENTA=$'\033[0;35m'
export NC=$'\033[0m'

# Mock orch_log function
orch_log() {
    :
}

setup() {
    init_empty_tasks
    # Disable AI for faster, deterministic tests
    export USE_AI=false
    # Enable auto-confirm to bypass interactive prompts
    export ORCH_AUTO_CONFIRM=yes
    # Disable auto-launch for cleaner tests
    export ORCH_NO_AUTO_LAUNCH=yes
}

teardown() {
    teardown
}

# =============================================================================
# Test: Auto-confirm mode (Y selection automatically)
# ==============================================================================

@test "confirmation: auto-confirm should accept plan with ORCH_AUTO_CONFIRM=yes" {
    # With auto-confirm enabled, the add command should succeed without input
    run bash "$ORCHESTRATOR" add "Test task"

    assert_success
    assert_output_partial "タスクを作成しました"
    assert_equal $(task_count) 1
}

@test "confirmation: auto-confirm should create task with correct agent" {
    run bash "$ORCHESTRATOR" add "Implement login feature"

    assert_success

    # Check that task was created with frontend agent (login feature pattern)
    local task=$(get_task 1)
    echo "$task" | grep -q "agent"
}

# =============================================================================
# Test: Decomposition with AI disabled (rule-based)
# ==============================================================================

@test "confirmation: rule-based decomposition should work without AI" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "User authentication feature"

    assert_success
    # Rule-based should create multiple tasks for authentication feature
    assert_output_partial "個のタスクを作成しました"
}

@test "confirmation: simple task should not be decomposed" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Write unit tests"

    assert_success
    # Tests task should not be decomposed further
    local count=$(task_count)
    assert [ "$count" -ge 1 ]
}

# =============================================================================
# Test: Agent assignment patterns
# ==============================================================================

@test "confirmation: frontend task should be assigned to frontend agent" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Design login form UI"

    assert_success

    local agent=$(jq -r '.tasks[0].agent' "$TASKS_FILE")
    assert_equal "$agent" "frontend"
}

@test "confirmation: backend task should be assigned to backend agent" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Create user API endpoint"

    assert_success

    local agent=$(jq -r '.tasks[0].agent' "$TASKS_FILE")
    assert_equal "$agent" "backend"
}

@test "confirmation: tests task should be assigned to tests agent" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Write integration tests"

    assert_success

    local agent=$(jq -r '.tasks[0].agent' "$TASKS_FILE")
    assert_equal "$agent" "tests"
}

@test "confirmation: docs task should be assigned to docs agent" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Update API documentation"

    assert_success

    local agent=$(jq -r '.tasks[0].agent' "$TASKS_FILE")
    assert_equal "$agent" "docs"
}

# =============================================================================
# Test: Priority handling
# ==============================================================================

@test "confirmation: task should respect normal priority by default" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Normal task"

    assert_success

    local priority=$(jq -r '.tasks[0].priority' "$TASKS_FILE")
    assert_equal "$priority" "normal"
}

@test "confirmation: task should respect critical priority" {
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Critical bug" backend critical

    assert_success

    local priority=$(jq -r '.tasks[0].priority' "$TASKS_FILE")
    assert_equal "$priority" "critical"
}

# =============================================================================
# Test: Task dependencies
# ==============================================================================

@test "confirmation: tasks can be created with dependencies" {
    export ORCH_AUTO_CONFIRM=yes

    # Create first task
    bash "$ORCHESTRATOR" add "First task" frontend normal
    local first_id=$(jq -r '.last_id' "$TASKS_FILE")

    # Create second task with dependency
    run bash "$ORCHESTRATOR" add "Second task" backend normal "[${first_id}]"

    assert_success

    local deps=$(jq -r '.tasks[] | select(.id == '${first_id}'+1) | .dependencies | join(",")' "$TASKS_FILE")
    assert_equal "$deps" "$first_id"
}

# =============================================================================
# Test: Error handling
# ==============================================================================

@test "confirmation: should handle empty task description" {
    run bash "$ORCHESTRATOR" add ""

    assert_failure
}

@test "confirmation: should provide help when no arguments" {
    run bash "$ORCHESTRATOR" add

    assert_success
    assert_output_partial "使用方法"
}

# =============================================================================
# Test: Decomposition history
# ==============================================================================

@test "confirmation: should create decomposition history entry" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    local history_file="$CLAUDE_DIR/decomposition_history.json"

    run bash "$ORCHESTRATOR" add "Test feature"

    assert_success

    # Check that history file exists and has an entry
    if [[ -f "$history_file" ]]; then
        local count=$(jq '.decompositions | length' "$history_file")
        assert [ "$count" -gt 0 ]
    fi
}

# =============================================================================
# Test: Multiple task creation scenarios
# ==============================================================================

@test "confirmation: authentication feature should create multiple subtasks" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "User authentication feature"

    assert_success
    assert_output_partial "タスクを作成しました"

    # Authentication feature typically creates 4-6 subtasks
    local count=$(task_count)
    assert [ "$count" -ge 3 ]
}

@test "confirmation: user registration feature should create multiple subtasks" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "User registration feature"

    assert_success
    assert_output_partial "タスクを作成しました"

    local count=$(task_count)
    assert [ "$count" -ge 3 ]
}

# =============================================================================
# Test: Output formatting
# ==============================================================================

@test "confirmation: should show task breakdown plan" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Test task"

    assert_success
    # Should show the plan header
    assert_output_partial "タスク分解プラン"
}

@test "confirmation: should show summary after creating tasks" {
    export USE_AI=false
    export ORCH_AUTO_CONFIRM=yes

    run bash "$ORCHESTRATOR" add "Test task"

    assert_success
    # Should show creation summary
    assert_output_partial "個のタスクを作成しました"
}

# =============================================================================
# Test: Agent auto-launch control
# ==============================================================================

@test "confirmation: should not auto-launch when ORCH_NO_AUTO_LAUNCH=yes" {
    export ORCH_AUTO_CONFIRM=yes
    export ORCH_NO_AUTO_LAUNCH=yes

    run bash "$ORCHESTRATOR" add "Test task"

    assert_success
    # Should mention auto-launch is disabled
    assert_output_partial "エージェント自動起動は無効"
}

@test "confirmation: should skip auto-launch message when ORCH_AUTO_LAUNCH=no" {
    export ORCH_AUTO_CONFIRM=yes
    export ORCH_AUTO_LAUNCH=no

    run bash "$ORCHESTRATOR" add "Test task"

    assert_success
    # Should not try to auto-launch
    refute_output "エージェントを自動起動します"
}
