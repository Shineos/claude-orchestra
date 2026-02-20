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
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
GRAY=$'\033[0;37m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="${LOGS_DIR:-$CLAUDE_DIR/logs}"

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
        Frontend|FRONTEND|frontend)
            echo "$CYAN"
            ;;
        Backend|BACKEND|backend)
            echo "$GREEN"
            ;;
        Architect|ARCHITECT|architect)
            echo "$MAGENTA"
            ;;
        Reviewer|REVIEWER|reviewer)
            echo "$YELLOW"
            ;;
        Tests|TESTS|tests)
            echo "$BLUE"
            ;;
        Docs|DOCS|docs)
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

        # エージェント抽出 (形式: [AGENT] または (担当: AGENT))
        local agent=""
        local agent_pattern=""
        
        if [[ "$rest" =~ \[([A-Za-z]+)\] ]]; then
            agent="${BASH_REMATCH[1]}"
            rest="${rest#*\] }" # [AGENT] をメッセージから除去して表示するか？
            # agent.shの場合、メッセージ本文はその後ろ。
        elif [[ "$rest" =~ \(担当:\ ([A-Za-z0-9_-]+)(,\ .*)?\) ]]; then
            # orchestrator.sh の形式: (担当: agent, ...)
            agent="${BASH_REMATCH[1]}"
            # この場合はメッセージ内に残るが、ハイライトしたいので別途処理
            agent_pattern="(担当: $agent"
        fi

        local log_color=$(get_log_color "$level")
        local agent_color=$(get_agent_color "$agent")

        # 表示
        if [[ "$show_timestamp" == "true" ]]; then
            printf "${GRAY}[%s]${NC} " "${timestamp:0:16}"
        fi

        # [AGENT] 形式の場合は先頭に表示
        if [[ "$rest" =~ ^\ *\[${agent}\] ]]; then
             # Remove [AGENT] from rest to avoid duplicate if we rely on regex above?
             # Actually regex above `rest="${rest#*\] }"` removes it IF it matched `[[ "$rest" =~ \[([A-Za-z]+)\] ]]`.
             # So we are good.
             printf " ${agent_color}[%s]${NC}" "$agent"
        elif [[ -n "$agent" && -z "$agent_pattern" ]]; then
             # Extracted but not via (担当:), likely [AGENT]
             printf " ${agent_color}[%s]${NC}" "$agent"
        fi

        printf " ${log_color}%-7s${NC}" "$level"
        
        # メッセージ本文のハイライト
        if [[ -n "$agent_pattern" ]]; then
             # (担当: xxx) をハイライト
             # sedで置換は複雑なので、単純に表示
             # しかしユーザーは「背景色とか」と言っている。
             # エージェント名を強調表示
             # restの中の `(担当: agent` を `(担当: ${agent_color}agent${NC}` に置換
             local highlighted_rest=$(echo "$rest" | sed "s/担当: $agent/担当: ${agent_color}${agent}${NC}/g")
             printf " %b\n" "$highlighted_rest"
        else
             printf " %s\n" "$rest"
        fi
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

    # If Task ID filter is present, force search all logs to find task history
    if [[ -n "$TASK_FILTER_ID" ]]; then
        search_all="true"
    fi

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
    
    # Task ID Filter (extends agent filter)
    if [[ -n "$TASK_FILTER_ID" ]]; then
        local task_json="$CLAUDE_DIR/tasks.json"
        if [[ -f "$task_json" ]]; then
            # Get agent for the task
            local task_agent=$(jq -r --arg id "$TASK_FILTER_ID" '.tasks[] | select(.id == ($id|tonumber)) | .agent' "$task_json" 2>/dev/null)
            
            if [[ -n "$task_agent" && "$task_agent" != "null" ]]; then
                # Filter for Task ID OR Agent Name
                local agent_upper=$(echo "$task_agent" | tr '[:lower:]' '[:upper:]')
                # Escape brackets for grep if needed, but [ ] are fine in quotes usually or use -F? 
                # Better use egrep (-E)
                # Pattern: "\[#ID\]|\[AGENT\]"
                # We need to escape brackets for regex: \[#ID\]
                grep_filter="grep -E \"\[#${TASK_FILTER_ID}\]|\[${agent_upper}\]\""
                
                # Update visual filter text if empty
                if [[ -z "$agent_filter" ]]; then
                   LOG_FILTER="Task #$TASK_FILTER_ID ($task_agent)"
                fi
            else
                 # Fallback to just Task ID if agent not found
                 grep_filter="grep \"\[#${TASK_FILTER_ID}\]\""
            fi
        else
             grep_filter="grep \"\[#${TASK_FILTER_ID}\]\""
        fi
    elif [[ -n "$agent_filter" ]]; then
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
            # echo "Debug: $grep_filter '$log_file'" >> /tmp/debug_log.txt
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
        local log_date=$(date +"%Y-%m-%d")
        local agent_log="$LOGS_DIR/agent-${log_date}.log"
        local orch_log="$LOGS_DIR/orchestrator-${log_date}.log"

        # 利用可能なログファイルを収集
        local log_files=()
        [[ -f "$agent_log" ]] && log_files+=("$agent_log")
        [[ -f "$orch_log" ]] && log_files+=("$orch_log")

        if [[ ${#log_files[@]} -eq 0 ]]; then
            printf "${YELLOW}ログファイルが見つかりません。作成されるのを待ちます...${NC}\n"
            while [[ ! -f "$agent_log" && ! -f "$orch_log" ]]; do
                sleep 1
            done
            [[ -f "$agent_log" ]] && log_files+=("$agent_log")
            [[ -f "$orch_log" ]] && log_files+=("$orch_log")
        fi

        # フィルタパターンの構築
        local filter_pattern=""
        
        # Task ID Filter logic
        if [[ -n "$TASK_FILTER_ID" ]]; then
            local task_json="$CLAUDE_DIR/tasks.json"
             if [[ -f "$task_json" ]]; then
                local task_agent=$(jq -r --arg id "$TASK_FILTER_ID" '.tasks[] | select(.id == ($id|tonumber)) | .agent' "$task_json" 2>/dev/null)
                if [[ -n "$task_agent" && "$task_agent" != "null" ]]; then
                    local agent_upper=$(echo "$task_agent" | tr '[:lower:]' '[:upper:]')
                    # Escape for regex: [#ID] -> \[\#ID\]
                    filter_pattern="\[#${TASK_FILTER_ID}\]|\[${agent_upper}\]"
                else
                    filter_pattern="\[#${TASK_FILTER_ID}\]"
                fi
             else
                 filter_pattern="\[#${TASK_FILTER_ID}\]"
             fi
        elif [[ -n "$agent_filter" ]]; then
            local agent_upper=$(echo "$agent_filter" | tr '[:lower:]' '[:upper:]')
            filter_pattern="\[${agent_upper}\]"
        fi

        # 履歴の表示 (最新50件)
        # 全ログファイルから検索して時系列順に表示
        if [[ -n "$filter_pattern" ]]; then
            # printf "${GRAY}--- 履歴 (最新50件) ---${NC}\n"
            
            # grepコマンド構築 (履歴用)
            # findで全ログファイルを取得し、xargs grepで検索
            # エラーフィルタがある場合は追加
            
            local history_cmd="find \"$LOGS_DIR\" -name \"*.log\" -type f -print0 | xargs -0 grep -h -E -- \"$filter_pattern\""
            
            if [[ "$errors_only" == "true" ]]; then
                history_cmd="$history_cmd | grep -i error"
            fi
            
            # sortで時系列順に並べ替え (ログはタイムスタンプで始まるため)
            history_cmd="$history_cmd | sort | tail -n 50"
            
            eval "$history_cmd" | while read -r line; do
                 parse_and_display_log "$line"
            done
            # printf "${GRAY}------------------------${NC}\n"
        fi

        # tail -f でフォロー (ライブ監視)
        local tail_grep_cmd=""
        if [[ -n "$filter_pattern" ]]; then
            tail_grep_cmd="grep -E --line-buffered -- \"$filter_pattern\""
        fi

        # Combine with error filter if needed
        if [[ "$errors_only" == "true" ]]; then
             if [[ -n "$tail_grep_cmd" ]]; then
                 tail_grep_cmd="$tail_grep_cmd | grep -i --line-buffered error"
             else
                 tail_grep_cmd="grep -i --line-buffered error"
             fi
        fi

        # Execute: tail both files
        if [[ -n "$tail_grep_cmd" ]]; then
             local full_cmd="tail -f ${log_files[*]} 2>/dev/null | $tail_grep_cmd"
             eval "$full_cmd" | while read -r line; do
                 [[ "$line" == "==>"* ]] && continue
                 [[ -z "$line" ]] && continue
                 clear_line
                 parse_and_display_log "$line"
             done
        else
            tail -f "${log_files[@]}" 2>/dev/null | while read -r line; do
                [[ "$line" == "==>"* ]] && continue
                [[ -z "$line" ]] && continue
                clear_line
                parse_and_display_log "$line"
            done
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
    if [[ -n "$TASK_FILTER_ID" ]]; then
        printf "${GRAY}💡 AIの思考プロセスを含む詳細ログを表示するには、ダッシュボードで 'v' を押してください${NC}\n"
    fi
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
            --task)
                # Task filtering: we will grep for [#ID] which is the standard log format for task actions
                if [[ -n "$2" ]]; then
                    LOG_FILTER="Task #$2"
                    task_id="$2"
                fi
                shift 2
                ;;
            --raw-task)
                # Display raw log file for the task
                if [[ -n "$2" ]]; then
                    task_id="$2"
                    mode="raw"
                fi
                shift 2
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
                # Unknown argument, ignore or show help. 
                # To prevent breaking if client sends something new, checking for -* usually helps, 
                # but let's assume anything else is an agent filter if not dashes.
                if [[ "$1" == -* ]]; then
                    shift 
                else
                    agent_filter="$1"
                    LOG_FILTER="$1"
                    shift
                fi
                ;;
        esac
    done

    # Add task filter to grep if task_id is set
    # Note: get_recent_logs and follow_logs need to handle this.
    # We will modify grep_filter construction in those functions usually, 
    # but here we can just pass it as an extra arg or sets global?
    # The functions take specific args. Let's export a global variable for task filter or refactor.
    # Simpler: Export TASK_FILTER_ID variable for the functions to use.
    export TASK_FILTER_ID="$task_id"

    if [[ "$mode" == "raw" ]]; then
        local raw_file="$LOGS_DIR/task-${task_id}.raw.log"
        if [[ -f "$raw_file" ]]; then
            printf "${CYAN}詳細タスクログ [#${task_id}]${NC} ${GRAY}(Ctrl+C で終了)${NC}\n"
            printf "${GRAY}ファイル: ${raw_file}${NC}\n"
            printf "${GRAY}────────────────────────────────────────────────────────────────${NC}\n"
            # 全内容を表示しつつ追従
            tail -f -n +1 "$raw_file"
            printf "\n${GRAY}────────────────────────────────────────────────────────────────${NC}\n"
        else
            printf "${RED}詳細ログが見つかりません: ${raw_file}${NC}\n"
            printf "タスクがまだ実行されていないか、ログがローテーションされた可能性があります。\n"
        fi
        return
    fi

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
