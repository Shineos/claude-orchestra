#!/bin/bash
# 承認管理機能モジュール
#
# このモジュールは orchestrator.sh から source して使用する
#

# ==============================================================================
# 承認データ管理
# ==============================================================================

# 承認データファイル
APPROVALS_FILE="$CLAUDE_DIR/approvals.json"

# 承認データファイルの初期化
init_approvals() {
    if [[ ! -f "$APPROVALS_FILE" ]]; then
        echo '{"approvals": [], "last_id": 0}' > "$APPROVALS_FILE"
    fi
}

# 承認ID生成
generate_approval_id() {
    local last_id
    last_id=$(jq -r '.last_id' "$APPROVALS_FILE" 2>/dev/null || echo "0")
    echo $((last_id + 1))
}

# ==============================================================================
# 承認リクエスト作成
# ==============================================================================

# 承認リクエストを作成
# 使用方法: request_approval <task_id> <operation_type> <details_json>
request_approval() {
    local task_id="$1"
    local operation_type="$2"
    local details_json="$3"

    if [[ -z "$task_id" || -z "$operation_type" ]]; then
        printf "%b" "${RED}エラー: タスクIDと操作種別は必須です${NC}\n"
        return 1
    fi

    init_approvals

    local approval_id
    approval_id=$(generate_approval_id)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local requested_by
    requested_by="${SUDO_USER:-${USER:-unknown}}"

    # 新しい承認リクエストを作成
    local new_approval
    new_approval=$(cat <<EOF
{
  "id": $(jq -n "$approval_id"),
  "task_id": "$task_id",
  "operation_type": "$operation_type",
  "details": $details_json,
  "requested_at": "$timestamp",
  "requested_by": "$requested_by",
  "status": "pending",
  "response": null
}
EOF
)

    # approvals.json に追加
    jq --argjson new "$new_approval" \
       '.approvals += [$new] | .last_id = ($new.id | tonumber)' \
       "$APPROVALS_FILE" > "${APPROVALS_FILE}.tmp" && \
       mv "${APPROVALS_FILE}.tmp" "$APPROVALS_FILE"

    orch_log "INFO" "承認リクエスト作成: #$approval_id (タスク#$task_id, 操作:$operation_type)"

    printf "%b" "${GREEN}✓ 承認リクエストを作成しました${NC}\n"
    echo "  リクエストID: #$approval_id"
    echo "  タスクID: #$task_id"
    echo "  操作種別: $operation_type"

    return 0
}

# ==============================================================================
# 承認待ち一覧表示
# ==============================================================================

# 承認待ちの一覧を表示
show_approval_queue() {
    init_approvals

    local pending_count
    pending_count=$(jq '[.approvals[] | select(.status == "pending")] | length' "$APPROVALS_FILE" 2>/dev/null || echo "0")

    if [[ "$pending_count" -eq 0 ]]; then
        printf "%b" "${CYAN}承認待ちのリクエストはありません${NC}\n"
        return 0
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  承認待ち一覧 (${pending_count}件)${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # テーブルヘッダー
    printf "${YELLOW}%-6s %-8s %-20s %-25s %-20s${NC}\n" "ID" "タスク" "操作種別" "詳細" "リクエスト日時"
    printf "%s\n" "────────────────────────────────────────────────────────────────────────────────────"

    # 承認待ちのリクエストを表示
    jq -r '.approvals[] | select(.status == "pending") |
           "\(.id)#\(.task_id)#\(.operation_type)#\(.details)#\(.requested_at)"' \
       "$APPROVALS_FILE" 2>/dev/null | while IFS='#' read -r id task_id op details requested_at; do
        # 詳細を短縮
        local short_details
        short_details=$(echo "$details" | jq -c 'if type == "object" then
            (if .file then "File: \(.file)" elif .command then "Cmd: \(.command)" else tojson end)
            else tojson end' 2>/dev/null | cut -c1-23)
        if [[ ${#short_details} -ge 23 ]]; then
            short_details="${short_details}..."
        fi

        # 日時を整形
        local date_formatted
        date_formatted=$(echo "$requested_at" | cut -c1-19 | tr 'T' ' ')

        printf "%-6s %-8s %-20s %-25s %-20s\n" \
            "#$id" "#$task_id" "$op" "$short_details" "$date_formatted"
    done

    echo ""
    echo "コマンド:"
    echo "  orch approve <id>     # 承認"
    echo "  orch reject <id>      # 却下"
}

# ==============================================================================
# 承認操作
# ==============================================================================

# 承認リクエストを承認
# 使用方法: approve_request <approval_id> [comment]
approve_request() {
    local approval_id="$1"
    local comment="${2:-}"

    if [[ -z "$approval_id" ]]; then
        printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
        return 1
    fi

    init_approvals

    # 承認リクエストの存在確認
    local exists
    exists=$(jq -r --arg id "$approval_id" \
                   '.approvals[] | select(.id == ($id | tonumber) and .status == "pending") | .id' \
                   "$APPROVALS_FILE" 2>/dev/null)

    if [[ -z "$exists" ]]; then
        printf "%b" "${RED}エラー: 承認リクエスト #$approval_id が見つからないか、既に処理されています${NC}\n"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local responded_by
    responded_by="${SUDO_USER:-${USER:-unknown}}"

    # 承認ステータスを更新
    jq --arg id "$approval_id" \
       --arg timestamp "$timestamp" \
       --arg responded_by "$responded_by" \
       --arg comment "$comment" \
       '(.approvals[] | select(.id == ($id | tonumber))) |= . + {
           status: "approved",
           response: {
               action: "approved",
               responded_at: $timestamp,
               responded_by: $responded_by,
               comment: (if $comment == "" then null else $comment end)
           }
       }' \
       "$APPROVALS_FILE" > "${APPROVALS_FILE}.tmp" && \
       mv "${APPROVALS_FILE}.tmp" "$APPROVALS_FILE"

    orch_log "INFO" "承認リクエスト承認: #$approval_id"

    printf "%b" "${GREEN}✓ 承認リクエスト #$approval_id を承認しました${NC}\n"
    if [[ -n "$comment" ]]; then
        echo "  コメント: $comment"
    fi

    return 0
}

# 承認リクエストを却下
# 使用方法: reject_request <approval_id> <reason>
reject_request() {
    local approval_id="$1"
    local reason="$2"

    if [[ -z "$approval_id" ]]; then
        printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
        return 1
    fi

    if [[ -z "$reason" ]]; then
        printf "%b" "${RED}エラー: 却下理由を指定してください${NC}\n"
        return 1
    fi

    init_approvals

    # 承認リクエストの存在確認
    local exists
    exists=$(jq -r --arg id "$approval_id" \
                   '.approvals[] | select(.id == ($id | tonumber) and .status == "pending") | .id' \
                   "$APPROVALS_FILE" 2>/dev/null)

    if [[ -z "$exists" ]]; then
        printf "%b" "${RED}エラー: 承認リクエスト #$approval_id が見つからないか、既に処理されています${NC}\n"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local responded_by
    responded_by="${SUDO_USER:-${USER:-unknown}}"

    # 却下ステータスを更新
    jq --arg id "$approval_id" \
       --arg timestamp "$timestamp" \
       --arg responded_by "$responded_by" \
       --arg reason "$reason" \
       '(.approvals[] | select(.id == ($id | tonumber))) |= . + {
           status: "rejected",
           response: {
               action: "rejected",
               responded_at: $timestamp,
               responded_by: $responded_by,
               reason: $reason
           }
       }' \
       "$APPROVALS_FILE" > "${APPROVALS_FILE}.tmp" && \
       mv "${APPROVALS_FILE}.tmp" "$APPROVALS_FILE"

    orch_log "INFO" "承認リクエスト却下: #$approval_id (理由: $reason)"

    printf "%b" "${YELLOW}✗ 承認リクエスト #$approval_id を却下しました${NC}\n"
    echo "  理由: $reason"

    return 0
}

# ==============================================================================
# 承認履歴表示
# ==============================================================================

# 承認履歴を表示
# 使用方法: show_approval_history [task_id]
show_approval_history() {
    local task_id="${1:-}"

    init_approvals

    if [[ -n "$task_id" ]]; then
        printf "%b" "${CYAN}タスク #$task_id の承認履歴${NC}\n"
    else
        printf "%b" "${CYAN}すべての承認履歴${NC}\n"
    fi

    echo ""

    local count
    count=$(jq ".approvals[] | select(.task_id == \"$task_id\" or \"$task_id\" == \"\")" "$APPROVALS_FILE" 2>/dev/null | wc -l)

    if [[ "$count" -eq 0 ]]; then
        printf "%b" "${YELLOW}承認履歴はありません${NC}\n"
        return 0
    fi

    # 履歴を表示
    jq -r --arg tid "$task_id" \
       ".approvals[] | select(.task_id == \$tid or \$tid == \"\") |
        \"\(.id)#\(.task_id)#\(.operation_type)#\(.status)#\(.requested_at)#\(.response.action // \"pending\")#\(.response.responded_at // \"-\")#\(.response.responded_by // \"-\")#\(.response.comment // .response.reason // \"\")\"" \
       "$APPROVALS_FILE" 2>/dev/null | while IFS='#' read -r id task_id op status req_at res_action res_at res_by note; do

        # ステータスに応じた色
        local status_color=""
        case "$status" in
            approved) status_color="$GREEN" ;;
            rejected) status_color="$RED" ;;
            pending) status_color="$YELLOW" ;;
            expired) status_color="$MAGENTA" ;;
        esac

        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        printf "${CYAN}承認リクエスト #${id}${NC}\n"
        printf "  タスクID: #${task_id}\n"
        printf "  操作種別: ${op}\n"
        printf "  ステータス: ${status_color}${status}${NC}\n"
        printf "  リクエスト日時: ${req_at}\n"

        if [[ "$res_action" != "pending" ]]; then
            printf "  応答: ${res_action}\n"
            printf "  応答日時: ${res_at}\n"
            printf "  応答者: ${res_by}\n"
            if [[ -n "$note" ]]; then
                printf "  メモ: ${note}\n"
            fi
        fi

        echo ""
    done
}

# ==============================================================================
# 承認ステータス確認
# ==============================================================================

# 指定した承認リクエストのステータスを確認
# 使用方法: check_approval_status <approval_id>
check_approval_status() {
    local approval_id="$1"

    if [[ -z "$approval_id" ]]; then
        printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
        return 1
    fi

    init_approvals

    local result
    result=$(jq -r --arg id "$approval_id" \
                   '.approvals[] | select(.id == ($id | tonumber)) |
                    "\(.status)#\(.response.action // "pending")"' \
                   "$APPROVALS_FILE" 2>/dev/null)

    if [[ -z "$result" ]]; then
        printf "%b" "${RED}承認リクエスト #$approval_id が見つかりません${NC}\n"
        return 1
    fi

    IFS='#' read -r status action <<< "$result"

    case "$status" in
        pending)
            printf "%b" "${YELLOW}pending${NC} - 承認待ち\n"
            return 0
            ;;
        approved)
            printf "%b" "${GREEN}approved${NC} - 承認済み\n"
            return 0
            ;;
        rejected)
            printf "%b" "${RED}rejected${NC} - 却下済み\n"
            return 1
            ;;
        *)
            printf "%b" "${MAGENTA}${status}${NC}\n"
            return 2
            ;;
    esac
}

# ==============================================================================
# ヘルプ表示
# ==============================================================================

show_approval_help() {
    cat <<'EOF'
承認管理コマンド:

  承認待ち一覧:
    orch approval-queue              # 承認待ちのリクエスト一覧を表示

  承認操作:
    orch approve <request_id>        # 承認リクエストを承認
        [--comment "comment"]        # オプションでコメントを追加

    orch reject <request_id>         # 承認リクエストを却下
        --reason "reason"            # 却下理由（必須）

  履歴表示:
    orch approval-history            # すべての承認履歴を表示
    orch approval-history <task_id>  # 特定タスクの履歴を表示

  ステータス確認:
    orch approval-status <request_id> # リクエストのステータスを確認

例:
  orch approval-queue
  orch approve 1
  orch approve 2 --comment "Looks good"
  orch reject 3 --reason "Security concern"
  orch approval-history 5

承認ステータス:
  pending   - 承認待ち
  approved  - 承認済み
  rejected  - 却下済み
  expired   - 期限切れ
EOF
}
