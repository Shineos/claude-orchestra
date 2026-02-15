#!/bin/bash
# CLI TUI Logs Viewer
#
# ターミナルベースのライブログビューアを表示します
#
# 使用方法:
#   ./tui-logs.sh                # 全ログ表示（最新20件）
#   ./tui-logs.sh --follow     # フォローモード（新着ログを自動表示）
#   ./tui-logs.sh --agent frontend  # エージェントフィルタ

set -e

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$CLAUDE_DIR/logs"

# デフォルト値
DEFAULT_LINES=20
LOG_FILTER=""

# =============================================================================
# ヘルパー関数
# =============================================================================

show_help() {
    cat << EOF
${CYAN}CLI TUI Logs Viewer${NC}

${YELLOW}使用方法:${NC}
    $0 [options] [agent]

${YELLOW}オプション:${NC}
    -f, --follow     フォローモード（新着ログを自動表示）
    -n, --lines N    表示するログ行数（デフォルト: 20）
    -e, --errors     エラーログのみ表示
    -a, --all        すべてのログファイルを検索

${YELLOW}エージェントフィルタ:${NC}
    frontend, backend, architect, reviewer, tests, docs

${YELLOW}例:${NC}
    $0                      # 最新20件を表示
    $0 -f                  # フォローモード
    $0 -f frontend         # Frontendログをフォロー
    $0 -n 50 -e backend    # Backendのエラー50件

EOF
}

# =============================================================================
# ログパース関数
# =============================================================================

# ログレベルの色を取得
get_log_color() {
    local level="$1"
    case "$level" in
        ERROR|error|ERR)
            echo "$RED"
            ;;
        WARN|warning|WARN)
            echo "$YELLOW"
            ;;
        SUCCESS|success|✓|✅)
            echo "$GREEN"
            ;;
        INFO|info)
            echo "$BLUE"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# エージェント名の色を取得
get_agent_color() {
    local agent="$1"
    case "$agent" in
        Frontend|FRONTEND)
            echo "$CYAN"
            ;;
        Backend|BACKEND)
            echo "$GREEN"
            ;;
        Architect|ARCHITECT)
            echo "$MAGENTA"
            ;;
        Reviewer|REVIEWER)
            echo "$YELLOW"
            ;;
        Tests|TESTS)
            echo "$BLUE"
            ;;
        Docs|DOCS)
            echo "$GRAY"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# ログ行をパースして表示
parse_and_display_log() {
    local line="$1"
    local show_timestamp="${2:-true}"

    # ログ形式をパース: [timestamp] [level] message
    if [[ "$line" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        local rest="${line#*\] }"

        # レベル抽出
        local level=""
        if [[ "$rest" =~ \[([A-Z]+)\] ]]; then
            level="${BASH_REMATCH[1]}"
            rest="${rest#*\] }"
        fi

        # エージェント抽出
        local agent=""
        if [[ "$rest" =~ \[([A-Za-z]+)\] ]]; then
            agent="${BASH_REMATCH[1]}"
            rest="${rest#*\] }"
        fi

        local log_color=$(get_log_color "$level")
        local agent_color=$(get_agent_color "$agent")

        # 表示
        if [[ "$show_timestamp" == "true" ]]; then
            printf "${GRAY}[%s]${NC} " "${timestamp:0:16}"
        fi

        if [[ -n "$agent" ]]; then
            printf " ${agent_color}[%s]${NC}" "$agent"
        fi

        printf " ${log_color}%-7s${NC}" "$level"
        printf " %s\n" "$rest"
    else
        # パースできない場合はそのまま表示
        printf "%s\n" "$line"
    fi
}

# =============================================================================
# ログ取得関数
# =============================================================================

# 最新ログを取得
get_recent_logs() {
    local lines="${1:-$DEFAULT_LINES}"
    local agent_filter="$2"
    local errors_only="$3"
    local search_all="$4"

    # 本日のログファイル
    local log_date=$(date +"%Y-%m-%d")
    local log_files=()

    if [[ "$search_all" == "true" ]]; then
        # すべてのログファイルを検索
        while IFS= read -r file; do
            [[ -f "$file" ]] && log_files+=("$file")
        done < <(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | sort -r)
    else
        # 本日のログファイル
        local agent_log="$LOGS_DIR/agent-$log_date.log"
        local orch_log="$LOGS_DIR/orchestrator-$log_date.log"

        [[ -f "$agent_log" ]] && log_files+=("$agent_log")
        [[ -f "$orch_log" ]] && log_files+=("$orch_log")
    fi

    # エージェントフィルタ
    local grep_filter=""
    if [[ -n "$agent_filter" ]]; then
        local agent_upper=$(echo "$agent_filter" | tr '[:lower:]' '[:upper:]')
        grep_filter="grep -i \"\[${agent_upper}\]\""
    fi

    # エラーフィルタ
    if [[ "$errors_only" == "true" ]]; then
        if [[ -n "$grep_filter" ]]; then
            grep_filter="$grep_filter | grep -i error"
        else
            grep_filter="grep -i error"
        fi
    fi

    # ログを読み取り
    for log_file in "${log_files[@]}"; do
        if [[ -n "$grep_filter" ]]; then
            eval "$grep_filter '$log_file' 2>/dev/null | tail -n $lines"
        else
            tail -n "$lines" "$log_file" 2>/dev/null
        fi
    done
}

# =============================================================================
# フォローモード
# =============================================================================

follow_logs() {
    local agent_filter="$1"
    local errors_only="$2"

    printf "\n${CYAN}フォローモード開始... (Ctrl+C で終了)${NC}\n"
    printf "${GRAY}═══════════════════════════════════════════════════════════════════${NC}\n\n"

    if command -v tail &> /dev/null; then
        local log_file="$LOGS_DIR/agent-$(date +"%Y-%m-%d").log"

        if [[ ! -f "$log_file" ]]; then
            printf "${YELLOW}警告: 本日のログファイルがありません${NC}\n"
            return
        fi

        # tail -f でフォロー
        if [[ -n "$agent_filter" ]]; then
            local agent_upper=$(echo "$agent_filter" | tr '[:lower:]' '[:upper:]')
            if [[ "$errors_only" == "true" ]]; then
                tail -f "$log_file" 2>/dev/null | grep -i --line-buffered "\[${agent_upper}\]" | grep -i --line-buffered error | while read -r line; do
                    clear_line
                    parse_and_display_log "$line"
                done
            else
                tail -f "$log_file" 2>/dev/null | grep -i --line-buffered "\[${agent_upper}\]" | while read -r line; do
                    clear_line
                    parse_and_display_log "$line"
                done
            fi
        else
            if [[ "$errors_only" == "true" ]]; then
                tail -f "$log_file" 2>/dev/null | grep -i --line-buffered error | while read -r line; do
                    clear_line
                    parse_and_display_log "$line"
                done
            else
                tail -f "$log_file" 2>/dev/null | while read -r line; do
                    clear_line
                    parse_and_display_log "$line"
                done
            fi
        fi
    else
        printf "${RED}エラー: tail コマンドが見つかりません${NC}\n"
    fi
}

# 行をクリア（キャリッジリターン）
clear_line() {
    printf "\r%80s\r" " "
}

# =============================================================================
# ヘッダー描画
# =============================================================================

draw_header() {
    clear

    printf "\n"
    printf "╔════════════════════════════════════════════════════════════════════╗\n"
    printf "║%b%-74s%b║\n" "$CYAN${BOLD}" "  Live Logs Viewer" "$NC"
    printf "╠════════════════════════════════════════════════════════════════════╣\n"
    printf "║  フィルタ: "

    if [[ -n "$LOG_FILTER" ]]; then
        printf "${CYAN}%s${NC}" "$LOG_FILTER"
    else
        printf "${GRAY}すべて${NC}"
    fi

    if [[ "$ERRORS_ONLY" == "true" ]]; then
        printf "  ${RED}(エラーのみ)${NC}"
    fi

    printf "                                            ║"
    printf "╚════════════════════════════════════════════════════════════════════╝\n"
    printf "\n"
}

# =============================================================================
# メイン処理
# =============================================================================

main() {
    local mode="normal"
    local lines="$DEFAULT_LINES"
    local agent_filter=""
    local errors_only="false"
    local search_all="false"

    # 引数解析
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow)
                mode="follow"
                shift
                ;;
            -n|--lines)
                lines="$2"
                shift 2
                ;;
            -e|--errors)
                errors_only="true"
                shift
                ;;
            -a|--all)
                search_all="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            frontend|backend|architect|reviewer|tests|docs)
                agent_filter="$1"
                LOG_FILTER="$1"
                shift
                ;;
            *)
                show_help
                exit 1
                ;;
        esac
    done

    if [[ "$mode" == "follow" ]]; then
        follow_logs "$agent_filter" "$errors_only"
    else
        draw_header

        local logs
        logs=$(get_recent_logs "$lines" "$agent_filter" "$errors_only" "$search_all")

        if [[ -z "$logs" ]]; then
            printf "${YELLOW}ログがありません${NC}\n"
            printf "\n"
            printf "ヒント:\n"
            printf "  • ${GREEN}orch start <agent>${NC} でエージェントを起動してください\n"
            printf "  • ${GREEN}orch add <task> <agent>${NC} でタスクを追加してください\n"
            return
        fi

        echo "$logs" | while IFS= read -r line; do
            parse_and_display_log "$line"
        done

        printf "\n"
        printf "${GRAY}────────────────────────────────────────────────────────────────${NC}\n"
        printf "コマンド:\n"
        printf "  ${GREEN}orch logs -f${NC}         - ライブログをフォロー\n"
        printf "  ${GREEN}orch logs -f frontend${NC} - エージェント指定でフォロー\n"
        printf "\n"
    fi
}

main "$@"
