#!/bin/bash
# CLI TUI Dashboard
#
# ターミナルベースのダッシュボードを表示します
#
# 使用方法:
#   ./tui-dashboard.sh           # 通常モード（1回のみ表示）
#   ./tui-dashboard.sh --watch   # ウォッチモード（5秒ごと更新）
#   ./tui-dashboard.sh --loop    # ループモード（Enterで更新）

set -e

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m'

# 太字
BOLD='\033[1m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$CLAUDE_DIR/tasks.json"
LOGS_DIR="$CLAUDE_DIR/logs"
PIDS_DIR="$CLAUDE_DIR/pids"

# =============================================================================
# データ取得関数
# =============================================================================

# タスク統計を取得
get_task_stats() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo '{"total":0,"completed":0,"in_progress":0,"pending":0,"review_needed":0,"rejected":0}'
        return
    fi

    jq -r '{
        total: (.tasks | length),
        completed: ([.tasks[] | select(.status == "completed")] | length),
        in_progress: ([.tasks[] | select(.status == "in_progress")] | length),
        pending: ([.tasks[] | select(.status == "pending")] | length),
        review_needed: ([.tasks[] | select(.status == "review_needed")] | length),
        rejected: ([.tasks[] | select(.status == "rejected")] | length)
    }' "$TASKS_FILE" 2>/dev/null || echo '{"total":0,"completed":0,"in_progress":0,"pending":0,"review_needed":0,"rejected":0}'
}

# エージェント状態を取得
get_agent_status() {
    local agents=("architect" "frontend" "backend" "reviewer" "tests" "docs")
    local result=()

    for agent in "${agents[@]}"; do
        local pid_file="$PIDS_DIR/${agent}.pid"
        local current_task=""

        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file" 2>/dev/null | cut -d':' -f1)
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                # 現在のタスクを取得
                current_task=$(jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent and (.status == "in_progress" or .status == "stopped")) | "\(.id): \(.description)"' "$TASKS_FILE" 2>/dev/null | head -1)
                result+=("$agent|active|$current_task")
                continue
            fi
        fi

        result+=("$agent|idle|")
    done

    printf '%s\n' "${result[@]}"
}

# エージェント別タスク数を取得
get_agent_task_counts() {
    jq -r '.tasks | group_by(.agent) | map({agent: .[0].agent, total: length, completed: ([.[] | select(.status == "completed")] | length), in_progress: ([.[] | select(.status == "in_progress")] | length)}) | sort_by(.agent)' "$TASKS_FILE" 2>/dev/null || echo '[]'
}

# 最新のログエントリを取得
get_recent_logs() {
    local log_file="$LOGS_DIR/agent-$(date +"%Y-%m-%d").log"

    if [[ ! -f "$log_file" ]]; then
        echo "[]"
        return
    fi

    # 最新のログを取得（ログ形式: [timestamp] [level] message）
    tail -n 10 "$log_file" 2>/dev/null | while IFS= read -r line; do
        # パースしてJSON配列として出力
        echo "$line"
    done
}

# =============================================================================
# 描画関数
# =============================================================================

# プログレスバー描画
draw_progress_bar() {
    local percentage=$1
    local width=${2:-30}
    local filled=$(( width * percentage / 100 ))
    local empty=$(( width - filled ))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percentage"
}

# ダッシュボード描画
draw_dashboard() {
    clear

    # ヘッダー
    printf "\n"
    printf "╔════════════════════════════════════════════════════════════════════╗\n"
    printf "║%b%-74s%b║\n" "$CYAN${BOLD}" "  Claude Orchestra Dashboard" "$NC"
    printf "╚════════════════════════════════════════════════════════════════════╝\n"
    printf "\n"

    # 更新時刻
    local update_time=$(date +"%Y-%m-%d %H:%M:%S")
    printf "${GRAY}最終更新: ${update_time}${NC}"
    printf "\n\n"

    # プロジェクト概要
    printf "%b${BOLD}📊 プロジェクト概要${NC}\n"
    printf "────────────────────────────────────────────────────────────────\n\n"

    local stats
    stats=$(get_task_stats)
    local total=$(echo "$stats" | jq -r '.total')
    local completed=$(echo "$stats" | jq -r '.completed')
    local in_progress=$(echo "$stats" | jq -r '.in_progress')
    local pending=$(echo "$stats" | jq -r '.pending')
    local review_needed=$(echo "$stats" | jq -r '.review_needed')
    local rejected=$(echo "$stats" | jq -r '.rejected')

    local completion_rate=0
    if [[ $total -gt 0 ]]; then
        completion_rate=$(( completed * 100 / total ))
    fi

    printf "  全タスク      "
    printf "  ${BOLD}${CYAN}│${BOLD}%-44s${BOLD}│ ${CYAN}%s${NC}\n" "" "$total"

    printf "  完了        "
    printf "  ${BOLD}${GREEN}│${BOLD}%-44s${BOLD}│ ${GREEN}%s${NC} " "" "$completed"
    draw_progress_bar "$completion_rate" 10
    printf "\n"

    printf "  進行中      "
    printf "  ${BOLD}${YELLOW}│${BOLD}%-44s${BOLD}│ ${YELLOW}%s${NC}\n" "" "$in_progress"

    printf "  保留中      "
    printf "  ${BOLD}${GRAY}│${BOLD}%-44s${BOLD}│ ${GRAY}%s${NC}\n" "" "$pending"

    printf "  レビュー中   "
    printf "  ${BOLD}${MAGENTA}│${BOLD}%-44s${BOLD}│ ${MAGENTA}%s${NC}\n" "" "$review_needed"

    printf "  却下        "
    printf "  ${BOLD}${RED}│${BOLD}%-44s${BOLD}│ ${RED}%s${NC}\n\n" "" "$rejected"

    # エージェント状態
    printf "%b${BOLD}🤖 エージェント状態${NC}\n"
    printf "────────────────────────────────────────────────────────────────\n\n"

    local agent_status
    agent_status=$(get_agent_status)

    echo "$agent_status" | while IFS='|' read -r name status task; do
        local status_icon=""
        local status_color=""

        case "$status" in
            active)
                status_icon="●"
                status_color="$GREEN"
                ;;
            idle)
                status_icon="○"
                status_color="$GRAY"
                ;;
        esac

        local agent_name_cap=$(echo "$name" | sed 's/./\U&/')
        printf "  ${status_color}${status_icon}${NC} ${BOLD}%-10s${NC}" "$agent_name_cap"

        if [[ "$status" == "active" && -n "$task" ]]; then
            local task_id=$(echo "$task" | cut -d':' -f1)
            local task_desc=$(echo "$task" | cut -d':' -f2-)
            if [[ ${#task_desc} -gt 40 ]]; then
                task_desc="${task_desc:0:37}..."
            fi
            printf "→ ${CYAN}#${task_id}${NC} $task_desc"
        else
            printf "  ${GRAY}待機中${NC}"
        fi
        printf "\n"
    done
    printf "\n"

    # エージェント別タスク統計
    printf "%b${BOLD}📈 エージェント別タスク数${NC}\n"
    printf "────────────────────────────────────────────────────────────────\n\n"

    local agent_counts
    agent_counts=$(get_agent_task_counts)

    echo "$agent_counts" | jq -r '.[] | @csv' 2>/dev/null | while IFS=',' read -r agent total completed inprog; do
        [[ -z "$agent" ]] && continue
        # Remove quotes from CSV output
        agent=$(echo "$agent" | tr -d '"')
        total=$(echo "$total" | tr -d '"')
        completed=$(echo "$completed" | tr -d '"')
        inprog=$(echo "$inprog" | tr -d '"')
        local agent_name_cap=$(echo "$agent" | sed 's/./\U&/')
        printf "  ${BOLD}%-10s${NC}" "$agent_name_cap"
        printf "  合計: ${CYAN}%s${NC}" "$total"
        printf "  完了: ${GREEN}%s${NC}" "$completed"
        printf "  進行中: ${YELLOW}%s${NC}" "$inprog"
        printf "\n"
    done
    printf "\n"

    # 最新ログ
    printf "%b${BOLD}📝 最新ログ - 最新5件${NC}\n"
    printf "────────────────────────────────────────────────────────────────\n\n"

    local recent_logs
    recent_logs=$(get_recent_logs)

    if [[ "$recent_logs" == "[]" ]] || [[ -z "$recent_logs" ]]; then
        printf "  ${GRAY}ログがありません${NC}\n\n"
    else
        echo "$recent_logs" | head -n 5 | while IFS= read -r line; do
            # ログレベルに応じて色分け
            local log_color="$NC"
            if [[ "$line" =~ \[ERROR\] ]]; then
                log_color="$RED"
            elif [[ "$line" =~ \[WARN\] ]]; then
                log_color="$YELLOW"
            elif [[ "$line" =~ \[SUCCESS\] ]] || [[ "$line" =~ ✓ ]]; then
                log_color="$GREEN"
            fi

            printf "  ${log_color}${line:0:80}${NC}\n"
        done
        printf "\n"
    fi

    # ヘルプ
    printf "────────────────────────────────────────────────────────────────\n"
    printf "コマンド:\n"
    printf "  ${GREEN}orch status${NC}         - タスク一覧表示"
    printf "  ${GREEN}orch board${NC}          - タスクボード TUI"
    printf "  ${GREEN}orch logs${NC}           - ライブログ TUI"
    printf "  ${GREEN}orch dashboard${NC}      - このダッシュボード"
    printf "\n"
}

# =============================================================================
# メイン処理
# =============================================================================

main() {
    local mode="${1:-}"

    case "$mode" in
        --watch|-w)
            # ウォッチモード
            if command -v watch &> /dev/null; then
                watch -n 5 -c "$0"
            else
                # watchがない場合は独自ループ
                while true; do
                    draw_dashboard
                    printf "\r${CYAN}次回更新: 5秒後... Ctrl+C で終了${NC}  "
                    sleep 5
                done
            fi
            ;;
        --loop|-l)
            # ループモード（Enterで更新）
            while true; do
                draw_dashboard
                printf "\n${CYAN}Enterキーで更新、Ctrl+C で終了...${NC} "
                read -r
            done
            ;;
        *)
            # 通常モード（1回のみ）
            draw_dashboard
            ;;
    esac
}

main "$@"
