#!/bin/bash
# CLI TUI Task Board
#
# ターミナルベースのタスクボード（カンバン形式）を表示します
#
# 使用方法:
#   ./tui-taskboard.sh           # 通常モード（1回のみ表示）
#   ./tui-taskboard.sh --watch   # ウォッチモード（5秒ごと更新）

set -e

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
WHITE='\033[1;37m'
NC='\033[0m'

# 太字
BOLD='\033[1m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$CLAUDE_DIR/tasks.json"

# カラム定義
declare -A COLUMN_NAMES=(
    ["pending"]="Pending      "
    ["in_progress"]="In Progress   "
    ["review_needed"]="Review Needed "
    ["completed"]="Completed     "
    ["rejected"]="Rejected      "
)

declare -A COLUMN_COLORS=(
    ["pending"]="$GRAY"
    ["in_progress"]="$YELLOW"
    ["review_needed"]="$MAGENTA"
    ["completed"]="$GREEN"
    ["rejected"]="$RED"
)

# =============================================================================
# データ取得関数
# =============================================================================

# カラムごとのタスクを取得
get_tasks_by_status() {
    local status="$1"
    jq -r --arg status "$status" \
        '.tasks[] | select(.status == $status) |
         "\(.id)|\(.description)|\(.agent)|\(.priority)"' \
        "$TASKS_FILE" 2>/dev/null || echo ""
}

# タスクカードを描画
draw_task_card() {
    local task_id="$1"
    local description="$2"
    local agent="$3"
    local priority="$4"
    local max_width=35

    # 説明を切り詰め
    local short_desc="$description"
    if [[ ${#short_desc} -gt $max_width ]]; then
        short_desc="${short_desc:0:$((max_width - 3))}..."
    fi

    # 優先度バッジ
    local priority_badge=""
    case "$priority" in
        high|critical)
            priority_badge="${RED}🔴${NC}"
            ;;
        normal|medium)
            priority_badge="${YELLOW}🟡${NC}"
            ;;
        low)
            priority_badge="${GREEN}🟢${NC}"
            ;;
    esac

    # エージェントバッジ
    local agent_cap=$(echo "$agent" | sed 's/./\U&/')
    local agent_badge="${CYAN}${agent_cap}${NC}"

    # カードを描画
    printf "┌────────────────────────────────────────┐\n"
    printf "│ #%-3s %s %s %-26s │\n" "$task_id" "$priority_badge" "$agent_badge" " "
    printf "│                                        │\n"
    printf "│ %-38s │\n" "$short_desc"
    printf "│                                        │\n"
    printf "└────────────────────────────────────────┘\n"
}

# タスクボード全体を描画
draw_taskboard() {
    clear

    # ヘッダー
    printf "\n"
    printf "╔════════════════════════════════════════════════════════════════════╗\n"
    printf "║%b%-74s%b║\n" "$CYAN${BOLD}" "  Task Board - Kanban View" "$NC"
    printf "╠════════════════════════════════════════════════════════════════════╣\n"
    printf "║  [+ 新規タスク: ${GREEN}orch add <task> <agent>${NC}]                      ║"
    printf "╠════════════════════════════════════════════════════════════════════╣\n"
    printf "║  [更新: Enter]  [終了: q/Ctrl+C]                                  ║"
    printf "╚════════════════════════════════════════════════════════════════════╝\n"
    printf "\n"

    # カラムヘッダー
    local header="┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐"
    local separator="│              │              │              │              │              │"

    echo "$header"
    printf "│"
    printf " ${BOLD}%-12s${NC} │" "Pending"
    printf " ${BOLD}%-12s${NC} │" "In Progress"
    printf " ${BOLD}%-12s${NC} │" "Review"
    printf " ${BOLD}%-12s${NC} │" "Completed"
    printf " ${BOLD}%-12s${NC} │" "Rejected"
    printf "\n"
    echo "$separator"

    # タスクデータを配列に格納（一時ファイルを使用）
    declare -a column_tasks_pending
    declare -a column_tasks_in_progress
    declare -a column_tasks_review_needed
    declare -a column_tasks_completed
    declare -a column_tasks_rejected

    get_tasks_by_status "pending" > /tmp/tasks_pending_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_pending+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_pending_$$.txt

    get_tasks_by_status "in_progress" > /tmp/tasks_inprogress_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_in_progress+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_inprogress_$$.txt

    get_tasks_by_status "review_needed" > /tmp/tasks_review_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_review_needed+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_review_$$.txt

    get_tasks_by_status "completed" > /tmp/tasks_completed_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_completed+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_completed_$$.txt

    get_tasks_by_status "rejected" > /tmp/tasks_rejected_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_rejected+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_rejected_$$.txt

    get_tasks_by_status "failed" > /tmp/tasks_failed_$$.txt
    while IFS='|' read -r task_id description agent priority; do
        [[ -z "$task_id" ]] && continue
        column_tasks_rejected+=("$task_id|$description|$agent|$priority")
    done < /tmp/tasks_failed_$$.txt

    rm -f /tmp/tasks_pending_$$.txt /tmp/tasks_inprogress_$$.txt /tmp/tasks_review_$$.txt /tmp/tasks_completed_$$.txt /tmp/tasks_rejected_$$.txt /tmp/tasks_failed_$$.txt

    # 最大行数を計算
    local max_lines=0
    local count_pending=${#column_tasks_pending[@]}
    local count_in_progress=${#column_tasks_in_progress[@]}
    local count_review=${#column_tasks_review_needed[@]}
    local count_completed=${#column_tasks_completed[@]}
    local count_rejected=${#column_tasks_rejected[@]}

    for count in $count_pending $count_in_progress $count_review $count_completed $count_rejected; do
        if [[ $count -gt $max_lines ]]; then
            max_lines=$count
        fi
    done

    # 最小でも5行は表示
    if [[ $max_lines -lt 5 ]]; then
        max_lines=5
    fi

    # 各行を描画
    for ((i=0; i<max_lines; i++)); do
        # セパレーター
        if [[ $i -gt 0 ]]; then
            printf "│              │              │              │              │              │\n"
        fi

        printf "│"

        # Pending カラム
        if [[ $i -lt ${#column_tasks_pending[@]} ]]; then
            local task="${column_tasks_pending[$i]}"
            IFS='|' read -r tid desc agt pri <<< "$task"
            local desc_short="$desc"
            [[ ${#desc_short} -gt 11 ]] && desc_short="${desc_short:0:9}.."
            local col_color="${COLUMN_COLORS[pending]}"
            printf " ${col_color}#%-2s${NC} %-9s" "$tid" "$desc_short"
        else
            printf " %14s" " "
        fi

        printf "│"

        # In Progress カラム
        if [[ $i -lt ${#column_tasks_in_progress[@]} ]]; then
            local task="${column_tasks_in_progress[$i]}"
            IFS='|' read -r tid desc agt pri <<< "$task"
            local desc_short="$desc"
            [[ ${#desc_short} -gt 11 ]] && desc_short="${desc_short:0:9}.."
            local col_color="${COLUMN_COLORS[in_progress]}"
            printf " ${col_color}#%-2s${NC} %-9s" "$tid" "$desc_short"
        else
            printf " %14s" " "
        fi

        printf "│"

        # Review Needed カラム
        if [[ $i -lt ${#column_tasks_review_needed[@]} ]]; then
            local task="${column_tasks_review_needed[$i]}"
            IFS='|' read -r tid desc agt pri <<< "$task"
            local desc_short="$desc"
            [[ ${#desc_short} -gt 11 ]] && desc_short="${desc_short:0:9}.."
            local col_color="${COLUMN_COLORS[review_needed]}"
            printf " ${col_color}#%-2s${NC} %-9s" "$tid" "$desc_short"
        else
            printf " %14s" " "
        fi

        printf "│"

        # Completed カラム
        if [[ $i -lt ${#column_tasks_completed[@]} ]]; then
            local task="${column_tasks_completed[$i]}"
            IFS='|' read -r tid desc agt pri <<< "$task"
            local desc_short="$desc"
            [[ ${#desc_short} -gt 11 ]] && desc_short="${desc_short:0:9}.."
            local col_color="${COLUMN_COLORS[completed]}"
            printf " ${col_color}#%-2s${NC} %-9s" "$tid" "$desc_short"
        else
            printf " %14s" " "
        fi

        printf "│"

        # Rejected カラム
        if [[ $i -lt ${#column_tasks_rejected[@]} ]]; then
            local task="${column_tasks_rejected[$i]}"
            IFS='|' read -r tid desc agt pri <<< "$task"
            local desc_short="$desc"
            [[ ${#desc_short} -gt 11 ]] && desc_short="${desc_short:0:9}.."
            local col_color="${COLUMN_COLORS[rejected]}"
            printf " ${col_color}#%-2s${NC} %-9s" "$tid" "$desc_short"
        else
            printf " %14s" " "
        fi

        printf "│\n"
    done

    # フッター
    printf "└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘\n"

    # 統計情報
    local total=$(jq '.tasks | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    local completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    local completion_rate=0
    if [[ $total -gt 0 ]]; then
        completion_rate=$(( completed * 100 / total ))
    fi

    printf "\n  総計: ${CYAN}%s${NC} タスク  " "$total"
    printf "完了: ${GREEN}%s${NC} (%d%%)  " "$completed" "$completion_rate"
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
                while true; do
                    draw_taskboard
                    printf "\r${CYAN}次回更新: 5秒後... (Ctrl+C で終了)${NC}  "
                    sleep 5
                done
            fi
            ;;
        --loop|-l)
            # ループモード（Enterで更新）
            while true; do
                draw_taskboard
                printf "\n${CYAN}Enterキーで更新、Ctrl+C で終了...${NC} "
                read -r
            done
            ;;
        *)
            # 通常モード（1回のみ）
            draw_taskboard
            ;;
    esac
}

main "$@"
