#!/usr/bin/env bats
# Unit tests for Approval System (approval.sh)

load '../helpers/bats_helper'

# Source the approval module functions
APPROVAL_MODULE="$PROJECT_ROOT/.claude/scripts/approval.sh"

# Set up required environment before loading the module
export CLAUDE_DIR="$PROJECT_ROOT/.claude"

# Color constants (required by approval.sh)
export RED=$'\033[0;31m'
export GREEN=$'\033[0;32m'
export YELLOW=$'\033[1;33m'
export BLUE=$'\033[0;34m'
export CYAN=$'\033[0;36m'
export MAGENTA=$'\033[0;35m'
export NC=$'\033[0m'

# Mock orch_log function (called by approval.sh)
orch_log() {
    local level="$1"
    local message="$2"
    # Silence logging in tests
    :
}

# Setup - bats_helper's setup() will be called automatically
setup() {
    # Initialize empty approvals file
    init_empty_approvals
    # Source the approval module to test its functions
    source "$APPROVAL_MODULE"
}

# =============================================================================
# Test: init_approvals function
# =============================================================================

@test "approval: init_approvals should create approvals.json if not exists" {
    # Remove existing approvals file
    rm -f "$APPROVALS_FILE"

    # Run init_approvals
    run init_approvals

    assert_success
    assert [[ -f "$APPROVALS_FILE" ]]

    # Verify structure
    local last_id=$(jq -r '.last_id' "$APPROVALS_FILE")
    assert_equal "$last_id" "0"
}

@test "approval: init_approvals should not overwrite existing approvals.json" {
    # Create approvals file with data
    echo '{"approvals": [{"id": 1}], "last_id": 5}' > "$APPROVALS_FILE"

    # Run init_approvals
    run init_approvals

    assert_success

    # Verify data was preserved
    local last_id=$(jq -r '.last_id' "$APPROVALS_FILE")
    assert_equal "$last_id" "5"
}

# =============================================================================
# Test: generate_approval_id function
# =============================================================================

@test "approval: generate_approval_id should return 1 for empty approvals" {
    init_empty_approvals

    run generate_approval_id

    assert_success
    assert_output "1"
}

@test "approval: generate_approval_id should increment from last_id" {
    echo '{"approvals": [], "last_id": 3}' > "$APPROVALS_FILE"

    run generate_approval_id

    assert_success
    assert_output "4"
}

# =============================================================================
# Test: request_approval function
# ==============================================================================

@test "approval: request_approval should create new approval request" {
    run request_approval "1" "file_write" '{"file":"test.txt","action":"create"}'

    assert_success
    assert_output_partial "承認リクエストを作成しました"
    assert_output_partial "リクエストID: #1"

    # Verify approval was created
    assert_equal $(approval_count) 1
    assert_approval_exists 1
    assert_approval_for_task 1 "1"
}

@test "approval: request_approval should fail with missing task_id" {
    run request_approval "" "test_operation" '{"test":"data"}'

    assert_failure
    assert_output_partial "エラー"
}

@test "approval: request_approval should fail with missing operation_type" {
    run request_approval "1" "" '{"test":"data"}'

    assert_failure
    assert_output_partial "エラー"
}

@test "approval: request_approval should create approval with correct status" {
    request_approval "1" "test_operation" '{"test":"data"}'

    assert_approval_status 1 "pending"
}

@test "approval: request_approval should increment approval_id sequentially" {
    request_approval "1" "op1" '{"type":"test"}'
    request_approval "2" "op2" '{"type":"test"}'
    request_approval "3" "op3" '{"type":"test"}'

    assert_equal $(approval_count) 3
    assert_approval_exists 1
    assert_approval_exists 2
    assert_approval_exists 3
}

# =============================================================================
# Test: approve_request function
# ==============================================================================

@test "approval: approve_request should approve pending request" {
    local approval_id=$(create_fixture_approval "1" "test_operation" '{"test":"data"}' "pending")

    run approve_request "$approval_id" "Looks good"

    assert_success
    assert_output_partial "承認リクエスト #$approval_id を承認しました"
    assert_approval_status "$approval_id" "approved"
}

@test "approval: approve_request should fail with missing approval_id" {
    run approve_request ""

    assert_failure
    assert_output_partial "エラー"
}

@test "approval: approve_request should fail for non-existent approval" {
    run approve_request "999"

    assert_failure
    assert_output_partial "見つからないか、既に処理されています"
}

@test "approval: approve_request should fail for already approved request" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "approved")

    run approve_request "$approval_id"

    assert_failure
    assert_output_partial "見つからないか、既に処理されています"
}

@test "approval: approve_request should store comment" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "pending")

    approve_request "$approval_id" "Test comment"

    local approval=$(get_approval "$approval_id")
    echo "$approval" | grep -q "Test comment"
}

@test "approval: approve_request should work without comment" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "pending")

    run approve_request "$approval_id"

    assert_success
    assert_approval_status "$approval_id" "approved"
}

# =============================================================================
# Test: reject_request function
# ==============================================================================

@test "approval: reject_request should reject pending request" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "pending")

    run reject_request "$approval_id" "Security concern"

    assert_success
    assert_output_partial "承認リクエスト #$approval_id を却下しました"
    assert_output_partial "理由: Security concern"
    assert_approval_status "$approval_id" "rejected"
}

@test "approval: reject_request should fail with missing approval_id" {
    run reject_request "" "Some reason"

    assert_failure
    assert_output_partial "エラー"
}

@test "approval: reject_request should fail with missing reason" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "pending")

    run reject_request "$approval_id" ""

    assert_failure
    assert_output_partial "エラー"
    assert_output_partial "却下理由を指定してください"
}

@test "approval: reject_request should fail for non-existent approval" {
    run reject_request "999" "Test reason"

    assert_failure
    assert_output_partial "見つからないか、既に処理されています"
}

@test "approval: reject_request should fail for already rejected request" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "rejected")

    run reject_request "$approval_id" "Another reason"

    assert_failure
}

# =============================================================================
# Test: show_approval_queue function
# ==============================================================================

@test "approval: show_approval_queue should show message when empty" {
    run show_approval_queue

    assert_success
    assert_output_partial "承認待ちのリクエストはありません"
}

@test "approval: show_approval_queue should display pending approvals" {
    create_fixture_approval "1" "file_write" '{"file":"test.txt"}' "pending"
    create_fixture_approval "2" "api_call" '{"endpoint":"/api/test"}' "pending"

    run show_approval_queue

    assert_success
    assert_output_partial "承認待ち一覧 (2件)"
    assert_output_partial "#1"
    assert_output_partial "#2"
    assert_output_partial "file_write"
    assert_output_partial "api_call"
}

@test "approval: show_approval_queue should not show approved approvals" {
    create_fixture_approval "1" "test_op" '{"test":"data"}' "approved"

    run show_approval_queue

    assert_success
    assert_output_partial "承認待ちのリクエストはありません"
    refute_output "#1"
}

@test "approval: show_approval_queue should not show rejected approvals" {
    create_fixture_approval "1" "test_op" '{"test":"data"}' "rejected"

    run show_approval_queue

    assert_success
    assert_output_partial "承認待ちのリクエストはありません"
}

# =============================================================================
# Test: check_approval_status function
# ==============================================================================

@test "approval: check_approval_status should fail for missing approval_id" {
    run check_approval_status ""

    assert_failure
    assert_output_partial "エラー"
}

@test "approval: check_approval_status should fail for non-existent approval" {
    run check_approval_status "999"

    assert_failure
    assert_output_partial "見つかりません"
}

@test "approval: check_approval_status should show pending status" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "pending")

    run check_approval_status "$approval_id"

    assert_success
    assert_output_partial "pending"
}

@test "approval: check_approval_status should show approved status" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "approved")

    run check_approval_status "$approval_id"

    assert_success
    assert_output_partial "approved"
}

@test "approval: check_approval_status should show rejected status" {
    local approval_id=$(create_fixture_approval "1" "test_op" '{"test":"data"}' "rejected")

    run check_approval_status "$approval_id"

    assert_failure
    assert_output_partial "rejected"
}

# =============================================================================
# Test: Edge cases
# ==============================================================================

@test "approval: should handle multiple pending approvals correctly" {
    create_fixture_approval "1" "op1" '{"test":"data"}' "pending"
    create_fixture_approval "2" "op2" '{"test":"data"}' "pending"
    create_fixture_approval "3" "op3" '{"test":"data"}' "approved"
    create_fixture_approval "4" "op4" '{"test":"data"}' "pending"

    run show_approval_queue

    assert_success
    assert_output_partial "(3件)"  # Only pending ones
}

@test "approval: should handle special characters in details" {
    run request_approval "1" "test" '{"file":"path/to/file with spaces.txt","action":"create"}'

    assert_success
    assert_equal $(approval_count) 1
}

@test "approval: should handle unicode in comments" {
    local approval_id=$(create_fixture_approval "1" "test" '{"test":"data"}' "pending")

    run approve_request "$approval_id" "日本語コメント OK ✅"

    assert_success

    local approval=$(get_approval "$approval_id")
    echo "$approval" | grep -q "日本語コメント"
}
