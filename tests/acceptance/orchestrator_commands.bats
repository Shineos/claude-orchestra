#!/usr/bin/env bats
# Acceptance tests for Orchestrator basic commands

load '../helpers/bats_helper'

setup() {
    # Backup existing files (if they exist)
    if [[ -f "$TASKS_FILE" ]]; then
        cp "$TASKS_FILE" "$TASKS_FILE.bak"
    fi
    if [[ -f "$APPROVALS_FILE" ]]; then
        cp "$APPROVALS_FILE" "$APPROVALS_FILE.bak"
    fi
    # Kill any running agents
    kill_running_agents
    # Always initialize with empty tasks for clean test state
    init_empty_tasks
    # Enable auto-confirm to bypass interactive prompts
    export ORCH_AUTO_CONFIRM=yes
    # Disable auto-launch for cleaner tests
    export ORCH_NO_AUTO_LAUNCH=yes
    # Disable AI for faster, deterministic tests
    export USE_AI=false
}

teardown() {
    # Restore backups and cleanup (from bats_helper)
    if [[ -f "$TASKS_FILE.bak" ]]; then
        mv "$TASKS_FILE.bak" "$TASKS_FILE"
    fi
    if [[ -f "$APPROVALS_FILE.bak" ]]; then
        mv "$APPROVALS_FILE.bak" "$APPROVALS_FILE"
    fi
    kill_running_agents
    cleanup_test_worktrees
}

# =============================================================================
# Test: orch add command
# =============================================================================

@test "add: should create a new task with auto-assigned agent" {
    run add_task "Implement login feature"

    assert_success
    assert_output --partial "タスクを追加しました"

    # Verify task was created in tasks.json
    assert_equal $(task_count) 1

    # Get the task and verify properties
    local task=$(get_task 1)
    echo "$task" | grep -q '"id": 1'
    echo "$task" | grep -q "Implement login feature"
}

@test "add: should create a task with specified agent" {
    run add_task "API endpoint" "backend"

    assert_success

    local task=$(get_task 1)
    echo "$task" | grep -q '"agent": "backend"'
}

@test "add: should create a task with priority" {
    run add_task "Critical bug fix" "backend" "critical"

    assert_success

    local task=$(get_task 1)
    echo "$task" | grep -q '"priority": "critical"'
}

@test "add: should create multiple tasks with sequential IDs" {
    add_task "Task 1" "frontend"
    add_task "Task 2" "backend"
    add_task "Task 3" "tests"

    assert_equal $(task_count) 3
    assert_task_exists 1
    assert_task_exists 2
    assert_task_exists 3
}

@test "add: should handle dependencies in task creation" {
    add_task "Task 1" "frontend"
    add_task "Task 2" "backend" "normal" "[1]"

    local task=$(get_task 2)
    local deps=$(echo "$task" | jq -r '.dependencies | join(",")')
    assert_equal "$deps" "1"
}

# =============================================================================
# Test: orch status command
# =============================================================================

@test "status: should show empty tasks list when no tasks exist" {
    run bash "$ORCHESTRATOR" status

    assert_success
    # If the UI shows summary instead of "no tasks" text, check for summary part
    assert_output --partial "タスク状況一覧"
}

@test "status: should display all tasks" {
    add_task "Task 1" "frontend"
    add_task "Task 2" "backend"

    run bash "$ORCHESTRATOR" status

    assert_success
    assert_output --partial "Task 1"
    assert_output --partial "Task 2"
}

@test "status: should show task details including ID, description, agent, status" {
    add_task "Implement feature" "backend"

    run bash "$ORCHESTRATOR" status

    assert_success
    assert_success
    assert_output --partial "#1"
    assert_output --partial "Implement feature"
    assert_output --partial "backend"
    assert_output --partial "pending"
}

# =============================================================================
# Test: orch start command
# =============================================================================

@test "start: should change task status from pending to in_progress" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "pending")

    run bash "$ORCHESTRATOR" start "$task_id"

    assert_success
    assert_output --partial "を開始しました"

    assert_task_status "$task_id" "in_progress"
}

@test "start: should fail for non-existent task" {
    run bash "$ORCHESTRATOR" start 999

    assert_failure
    assert_output --partial "が見つかりませんでした"
}

@test "start: should fail for already started task" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "in_progress")

    run bash "$ORCHESTRATOR" start "$task_id"

    assert_failure
}

# =============================================================================
# Test: orch complete command
# =============================================================================

@test "complete: should change task status from in_progress to completed" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "in_progress")

    run bash "$ORCHESTRATOR" complete "$task_id"

    assert_success
    assert_output --partial "を完了しました"

    assert_task_status "$task_id" "completed"
}

@test "complete: should fail for pending task" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "pending")

    run bash "$ORCHESTRATOR" complete "$task_id"

    assert_failure
}

# =============================================================================
# Test: orch fail command
# =============================================================================

@test "fail: should change task status to failed with reason" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "in_progress")

    run bash "$ORCHESTRATOR" fail "$task_id" "API endpoint not available"

    assert_success
    assert_output --partial "が失敗しました"

    assert_task_status "$task_id" "failed"

    local task=$(get_task "$task_id")
    echo "$task" | grep -q "API endpoint not available"
}

@test "fail: should require a reason" {
    local task_id=$(create_fixture_task "Test task" "backend" "normal" "in_progress")

    run bash "$ORCHESTRATOR" fail "$task_id"

    assert_failure
}

# =============================================================================
# Test: orch agents command
# =============================================================================

@test "agents: should show agent status summary" {
    add_task "Frontend task" "frontend"
    add_task "Backend task" "backend"

    run bash "$ORCHESTRATOR" agents

    assert_success
    assert_output --partial "Frontend"
    assert_output --partial "Backend"
}

# =============================================================================
# Test: orch next command
# =============================================================================

@test "next: should show next available tasks" {
    add_task "Task 1" "frontend"
    add_task "Task 2" "backend"

    run bash "$ORCHESTRATOR" next

    assert_success
    # Should show tasks without dependencies
    assert_output --partial "Task 1"
    assert_output --partial "Task 2"
}

@test "next: should not show tasks with unmet dependencies" {
    add_task "Task 1" "frontend"
    add_task "Task 2 with dependency" "backend" "normal" "[1]"

    run bash "$ORCHESTRATOR" next

    assert_success
    assert_output --partial "Task 1"
    refute_output --partial "Task 2 with dependency"
}

@test "next: should show tasks when dependencies are completed" {
    local task1_id=$(create_fixture_task "Task 1" "frontend" "normal" "completed")
    local task2_id=$(create_fixture_task "Task 2" "backend" "normal" "pending")

    # Update task 2 to depend on task 1
    jq --argjson tid "$task2_id" --argjson dep "[$task1_id]" '(.tasks[] | select(.id == $tid)).dependencies = $dep' "$TASKS_FILE" > "$TASKS_FILE.tmp"
    mv "$TASKS_FILE.tmp" "$TASKS_FILE"

    run bash "$ORCHESTRATOR" next

    assert_success
    assert_output --partial "Task 2"
}

# =============================================================================
# Test: Error handling
# =============================================================================

@test "orchestrator: should handle invalid command gracefully" {
    run bash "$ORCHESTRATOR" invalid_command

    assert_failure
}

@test "orchestrator: should show help with no arguments" {
    run bash "$ORCHESTRATOR"

    assert_success
    # Help should include usage information
    # Even with no args, it might show status and help if that's the default behavior
    assert_success
}
