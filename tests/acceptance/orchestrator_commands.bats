#!/usr/bin/env bats
# Acceptance tests for Orchestrator basic commands

load '../helpers/bats_helper'

setup() {
    # Call parent setup
    setup
    init_empty_tasks
    # Enable auto-confirm to bypass interactive prompts
    export ORCH_AUTO_CONFIRM=yes
    # Disable auto-launch for cleaner tests
    export ORCH_NO_AUTO_LAUNCH=yes
    # Disable AI for faster, deterministic tests
    export USE_AI=false
}

teardown() {
    # Call parent teardown
    teardown
}

# =============================================================================
# Test: orch add command
# =============================================================================

@test "add: should create a new task with auto-assigned agent" {
    run add_task "Implement login feature"

    assert_success
    assert_output --partial "タスクを作成しました"

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
    echo "$task" | grep -q '"dependencies": \[1\]'
}

# =============================================================================
# Test: orch status command
# =============================================================================

@test "status: should show empty tasks list when no tasks exist" {
    run bash "$ORCHESTRATOR" status

    assert_success
    assert_output --partial "タスクがありません"
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
    assert_output --partial "[1]"
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
    assert_output --partial "タスクを開始しました"

    assert_task_status "$task_id" "in_progress"
}

@test "start: should fail for non-existent task" {
    run bash "$ORCHESTRATOR" start 999

    assert_failure
    assert_output --partial "タスクが見つかりません"
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
    assert_output --partial "タスクを完了しました"

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
    assert_output --partial "タスクを失敗としてマークしました"

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
    jq "(.tasks[] | select(.id == $task2_id)) |= .dependencies = [$task1_id]" "$TASKS_FILE" > "$TASKS_FILE.tmp"
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
    assert_output --partial "使用方法"
}
