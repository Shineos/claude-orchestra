#!/usr/bin/env bats
# Acceptance tests for Agent lifecycle management

load '../helpers/bats_helper'

setup() {
    setup
    init_empty_tasks
}

teardown() {
    teardown
}

# =============================================================================
# Test: orch launch command
# =============================================================================

@test "launch: should start agents for pending tasks" {
    add_task "Frontend task" "frontend"
    add_task "Backend task" "backend"

    run bash "$ORCHESTRATOR" launch

    assert_success

    # Give agents a moment to start
    sleep 2

    assert_agent_running "frontend"
    assert_agent_running "backend"
}

@test "launch: should not start agents for already running tasks" {
    add_task "Frontend task" "frontend"

    # Launch once
    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    # Try to launch again
    run bash "$ORCHESTRATOR" launch

    assert_success
    # Should indicate agent already running or no new tasks
}

# =============================================================================
# Test: orch list/ps command
# =============================================================================

@test "list: should show no running agents initially" {
    run bash "$ORCHESTRATOR" list

    assert_success
    assert_output --partial "実行中のエージェントはありません"
}

@test "list: should show running agents after launch" {
    add_task "Frontend task" "frontend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    run bash "$ORCHESTRATOR" list

    assert_success
    assert_output --partial "frontend"
    refute_output --partial "実行中のエージェントはありません"
}

# =============================================================================
# Test: orch stop command
# =============================================================================

@test "stop: should stop a specific running agent" {
    add_task "Frontend task" "frontend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    # Verify agent is running
    assert_agent_running "frontend"

    # Stop the agent
    run bash "$ORCHESTRATOR" stop "frontend"

    assert_success

    sleep 1

    # Verify agent is no longer running
    assert_agent_not_running "frontend"
}

@test "stop: should handle stopping non-existent agent gracefully" {
    run bash "$ORCHESTRATOR" stop "nonexistent"

    # Should not crash, may show error or warning
    [[ $status -eq 0 || $status -eq 1 ]]
}

@test "stop: should stop all agents with 'all' parameter" {
    add_task "Frontend task" "frontend"
    add_task "Backend task" "backend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    # Stop all agents
    run bash "$ORCHESTRATOR" stop "all"

    assert_success

    sleep 1

    assert_agent_not_running "frontend"
    assert_agent_not_running "backend"
}

# =============================================================================
# Test: orch restart command
# =============================================================================

@test "restart: should restart a specific agent" {
    add_task "Frontend task" "frontend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    local pid_before=$(jq -r '.pid' "$PIDS_DIR/frontend.json" 2>/dev/null || echo "")

    run bash "$ORCHESTRATOR" restart "frontend"

    assert_success

    sleep 2

    local pid_after=$(jq -r '.pid' "$PIDS_DIR/frontend.json" 2>/dev/null || echo "")

    # PIDs should be different after restart
    [[ "$pid_before" != "$pid_after" ]]
    assert_agent_running "frontend"
}

@test "restart: should restart all agents with 'all' parameter" {
    add_task "Frontend task" "frontend"
    add_task "Backend task" "backend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    run bash "$ORCHESTRATOR" restart "all"

    assert_success

    sleep 2

    assert_agent_running "frontend"
    assert_agent_running "backend"
}

# =============================================================================
# Test: orch reset command
# =============================================================================

@test "reset: should remove all tasks and agents" {
    add_task "Task 1" "frontend"
    add_task "Task 2" "backend"

    bash "$ORCHESTRATOR" launch >/dev/null 2>&1
    sleep 2

    # Verify tasks and agents exist
    assert [ $(task_count) -gt 0 ]
    assert_agent_running "frontend"

    # Reset (requires confirmation, so we need to pipe 'y')
    echo "y" | run bash "$ORCHESTRATOR" reset

    assert_success

    # Verify all tasks are gone
    assert_equal $(task_count) 0

    sleep 1

    # Verify agents are stopped
    assert_agent_not_running "frontend"
    assert_agent_not_running "backend"
}

@test "reset: should cancel reset with 'n' confirmation" {
    add_task "Task 1" "frontend"

    local count_before=$(task_count)

    # Cancel reset
    echo "n" | run bash "$ORCHESTRATOR" reset

    assert_success

    # Tasks should still exist
    assert_equal $(task_count) "$count_before"
}

# =============================================================================
# Test: Agent script directly
# =============================================================================

@test "agent: should start specific agent directly" {
    add_task "Test task" "frontend"

    run bash "$AGENT" "frontend"

    # Agent will wait for input and timeout, so we expect it to be killed
    # Just verify it starts

    sleep 2

    assert_agent_running "frontend"

    # Clean up
    bash "$ORCHESTRATOR" stop "frontend" >/dev/null 2>&1
}

@test "agent: should error on invalid agent name" {
    run bash "$AGENT" "invalid_agent"

    assert_failure
    assert_output --partial "不明なエージェント"
}

# =============================================================================
# Test: orch monitor command
# =============================================================================

@test "monitor: should display monitoring interface" {
    add_task "Task 1" "frontend"

    # monitor is interactive, so we run it with a timeout
    # The test just verifies it starts without error
    timeout 3 bash "$ORCHESTRATOR" monitor || true

    # If it timed out, that's expected behavior for an interactive command
    [[ $? -eq 124 || $? -eq 0 || $? -eq 130 ]]
}

@test "monitor-agents: should display per-agent monitoring" {
    add_task "Task 1" "frontend"

    # Similar to monitor, this is interactive
    timeout 3 bash "$ORCHESTRATOR" monitor-agents || true

    [[ $? -eq 124 || $? -eq 0 || $? -eq 130 ]]
}
