#!/bin/bash
# 承認管理コマンド ラッパー
#
# 使用方法:
#   ./approval-cmd.sh approval-queue
#   ./approval-cmd.sh approve <id> [--comment "comment"]
#   ./approval-cmd.sh reject <id> --reason "reason"
#   ./approval-cmd.sh approval-history [task_id]
#   ./approval-cmd.sh approval-status <id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR は .claude/scripts を指すので、その親が CLAUDE_DIR になる
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"

# 承認管理モジュールを読み込み
source "$SCRIPT_DIR/approval.sh"

# コマンド実行
case "${1:-}" in
    approval-queue)
        show_approval_queue
        ;;
    approve)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
            echo "使用方法: $0 approve <request_id> [--comment \"comment\"]"
            exit 1
        fi
        _req_id="$2"
        _comment=""
        shift 2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --comment)
                    _comment="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        approve_request "$_req_id" "$_comment"
        ;;
    reject)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
            echo "使用方法: $0 reject <request_id> --reason \"reason\""
            exit 1
        fi
        _req_id="$2"
        _reason=""
        shift 2
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --reason)
                    _reason="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        if [[ -z "$_reason" ]]; then
            printf "%b" "${RED}エラー: 却下理由を指定してください（--reason）${NC}\n"
            exit 1
        fi
        reject_request "$_req_id" "$_reason"
        ;;
    approval-history)
        show_approval_history "${2:-}"
        ;;
    approval-status)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: 承認リクエストIDを指定してください${NC}\n"
            echo "使用方法: $0 approval-status <request_id>"
            exit 1
        fi
        check_approval_status "$2"
        ;;
    approval-help|--help|-h)
        show_approval_help
        ;;
    *)
        printf "%b" "${RED}エラー: 不明なコマンド '$1'${NC}\n"
        echo ""
        show_approval_help
        exit 1
        ;;
esac
