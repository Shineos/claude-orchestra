#!/bin/bash
# エージェント起動スクリプト（タスク自動実行機能付き）
#
# 使用方法:
#   ./agent.sh <agent>
#
# 例:
#   ./agent.sh frontend    # Frontend エージェントを起動し、タスクを自動実行
#   ./agent.sh watch       # タスクを待機して自動実行

set -e

# 色設定（ANSI-C quotingでエスケープシーケンスを正しく解釈）
CYAN=$'\033[0;36m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# プロジェクトルート（.claude の親ディレクトリ）
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# タスクファイル
TASKS_FILE="$SCRIPT_DIR/tasks.json"

# ログディレクトリ
LOGS_DIR="$SCRIPT_DIR/logs"

# ログファイル（日付別）
LOG_DATE=$(date +"%Y-%m-%d")
LOG_FILE="$LOGS_DIR/agent-$LOG_DATE.log"

# ログディレクトリ作成
mkdir -p "$LOGS_DIR"

# Claude CLI タイムアウト設定（秒）
# タスク実行の最大待機時間。超過した場合はタイムアウトとして失敗します
# 環境変数で上書き可能、デフォルトは動的タイムアウトを使用
BASE_TIMEOUT="${BASE_TIMEOUT:-600}"  # ベースタイムアウト（10分）
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-}"  # 空なら動的タイムアウト使用

# PIDファイルディレクトリ
PIDS_DIR="$SCRIPT_DIR/pids"
mkdir -p "$PIDS_DIR"

# シグナルハンドリング
cleanup() {
    if [[ -n "${AGENT_NAME:-}" ]]; then
        rm -f "$PIDS_DIR/${AGENT_NAME}.pid"
        rm -f "$PIDS_DIR/${AGENT_NAME}.json"
    fi
}
trap cleanup EXIT SIGTERM SIGINT

# ==============================================================================
# ログ関数
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] [$level] $message"
    
    # stdoutに出力
    echo "$log_entry"
    
    # ログファイルにも追記
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# ==============================================================================
# タスク管理関数
# ==============================================================================

# エージェントの次のタスクを取得（優先度順）
get_next_task() {
    local agent="$1"
    if [[ -f "$TASKS_FILE" ]]; then
        # 依存関係が満たされた未着手タスクを取得
        # 優先度順でソート: critical(0) > high(1) > normal(2) > low(3)
        local result=$(jq -r --arg agent "$agent" '
            .tasks as $all_tasks
            | .tasks
            | map(select(.agent == $agent and .status == "pending"))
            | map(select(
                .dependencies == null or
                (.dependencies | length) == 0 or
                (.dependencies | map(. as $dep_id | $all_tasks[] | select(.id == $dep_id) | .status == "completed") | all)
            ))
            | sort_by(
                (if .priority == "critical" then 0 elif .priority == "high" then 1 elif .priority == "normal" then 2 else 3 end),
                .created_at
            )
            | .[0]
            | select(. != null)
            | "\(.id)\t\(.description)\t\(.priority // "normal")"
        ' "$TASKS_FILE" 2>/dev/null)

        # 結果がnullまたは空の場合は空文字を返す
        if [[ "$result" == "null" ]] || [[ -z "$result" ]]; then
            echo ""
        else
            echo "$result"
        fi
    fi
}

# タスクを開始
start_task() {
    local task_id="$1"
    local updated_tasks=$(jq --argjson id "$task_id" \
        --arg status "in_progress" \
        --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '(.tasks[] | select(.id == $id)) |= (.status = $status | .started_at = $started_at)' \
        "$TASKS_FILE")
    echo "$updated_tasks" > "$TASKS_FILE"
}

# タスクを完了
complete_task() {
    local task_id="$1"
    local result="${2:-success}"
    local updated_tasks=$(jq --argjson id "$task_id" \
        --arg status "completed" \
        --arg result "$result" \
        --arg completed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '(.tasks[] | select(.id == $id)) |= (.status = $status | .result = $result | .completed_at = $completed_at | .progress = 100)' \
        "$TASKS_FILE")
    echo "$updated_tasks" > "$TASKS_FILE"
}

# タスクを失敗
fail_task() {
    local task_id="$1"
    local reason="$2"
    local updated_tasks=$(jq --argjson id "$task_id" \
        --arg status "failed" \
        --arg result "$reason" \
        --arg completed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '(.tasks[] | select(.id == $id)) |= (.status = $status | .result = $result | .completed_at = $completed_at)' \
        "$TASKS_FILE")
    echo "$updated_tasks" > "$TASKS_FILE"
    log "ERROR" "タスク失敗: #$task_id - $reason"
}

# ==============================================================================
# エージェント読み込み
# ==============================================================================

load_agent() {
    local agent=$1
    local agent_file="$SCRIPT_DIR/agents/${agent}.json"

    if [[ -f "$agent_file" ]]; then
        jq -r '.system_prompt' "$agent_file" 2>/dev/null
    else
        # デフォルトのシステムプロンプト
        echo "あなたは${agent}エージェントとして、以下のタスクを実行してください。"
    fi
}

# ==============================================================================
# 動的タイムアウト計算
# ==============================================================================

# タスクの複雑さに基づいてタイムアウト時間を動的に計算
calculate_dynamic_timeout() {
    local task_desc="$1"
    local task_desc_lower=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')
    local timeout="$BASE_TIMEOUT"

    # 複雑なタスクキーワード（×3 = 30分）
    local complex_keywords=(
        "実装" "implement" "作成" "create" "build" "構築"
        "設計" "design" "architecture" "アーキテクチャ"
        "統合" "integrate" "integration" "連携"
        "マイグレーション" "migration" "移行"
    )

    # 中程度のタスクキーワード（×2 = 20分）
    local medium_keywords=(
        "修正" "fix" "update" "更新" "変更" "change"
        "追加" "add" "拡張" "extend" "enhance"
        "リファクタ" "refactor" "改善" "improve"
        "テスト" "test" "spec"
    )

    # 複雑なタスクかチェック
    for keyword in "${complex_keywords[@]}"; do
        if [[ "$task_desc_lower" == *"$keyword"* ]]; then
            timeout=$((BASE_TIMEOUT * 3))
            log "INFO" "複雑なタスクを検出: '$keyword' -> タイムアウト ${timeout}秒" >&2
            echo "$timeout"
            return 0
        fi
    done

    # 中程度のタスクかチェック
    for keyword in "${medium_keywords[@]}"; do
        if [[ "$task_desc_lower" == *"$keyword"* ]]; then
            timeout=$((BASE_TIMEOUT * 2))
            log "INFO" "中程度のタスクを検出: '$keyword' -> タイムアウト ${timeout}秒" >&2
            echo "$timeout"
            return 0
        fi
    done

    # デフォルト（ベースタイムアウト）
    log "INFO" "標準タスク -> タイムアウト ${timeout}秒" >&2
    echo "$timeout"
}

# 現在のタスクのタイムアウトを取得（環境変数または動的計算）
get_task_timeout() {
    local task_desc="$1"

    # 環境変数が設定されている場合はそれを優先
    if [[ -n "$CLAUDE_TIMEOUT" ]]; then
        echo "$CLAUDE_TIMEOUT"
    else
        calculate_dynamic_timeout "$task_desc"
    fi
}

# ==============================================================================
# タスク実行
# ==============================================================================

execute_task() {
    local agent="$1"
    local task_id="$2"
    local task_desc="$3"
    local system_prompt=$(load_agent "$agent")



    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク実行中${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}タスクID: ${NC}#$task_id\n"
    printf "%b" "${YELLOW}エージェント: ${NC}$agent\n"
    printf "%b" "${YELLOW}説明: ${NC}$task_desc\n"
    echo ""
    printf "%b" "${BLUE}Claude Codeで実行中...${NC}\n"
    echo ""

    log "INFO" "開始: [#$task_id] $task_desc"

    # Claude CLIでタスクを実行（非対話モード）
    local prompt="${system_prompt}"$'\n\n'
    prompt+="タスク: ${task_desc}"$'\n\n'
    prompt+="プロジェクトルート: ${PROJECT_ROOT}"$'\n\n'
    prompt+="注意事項:"$'\n'
    prompt+="- プロジェクトの既存コードを理解してから変更を加えてください"$'\n'
    prompt+="- 小さく変更してテストしてください"$'\n'
    prompt+="- エラーがあればログを確認してください"$'\n'
    prompt+="- 完了したら変更内容を報告してください"

    # 現在の作業ディレクトリを保存
    local current_dir=$(pwd)

    # プロジェクトルートに移動してClaude CLIを実行
    cd "$PROJECT_ROOT"

    # 動的タイムアウトを計算
    local task_timeout=$(get_task_timeout "$task_desc")

    # Claude CLIを実行（-pフラグで非対話モード）
    # EOFをパイプして処理後に終了させる
    # タイムアウト付き実行（macOS対応: Perlのalarmを使用）
    local output
    local exit_code
    local start_time=$(date +%s)

    # 詳細ログ用タイムスタンプ
    local exec_start_ts=$(date +"%Y-%m-%d %H:%M:%S")
    log "INFO" "Claude CLI実行開始: $exec_start_ts"
    log "INFO" "  タスク: [#$task_id] $task_desc"
    log "INFO" "  タイムアウト設定: ${task_timeout}秒（動的調整）"

    # Perlのalarm機能でタイムアウトを実装（macOSのtimeoutコマンドなし対応）
    # --verboseフラグで詳細ログ（思考プロセスなど）を出力
    output=$(perl -e "alarm $task_timeout; exec @ARGV;" \
        /bin/bash -c "echo \"\" | claude -p --verbose --system-prompt \"$system_prompt\" \"$prompt\" 2>&1" \
        2>&1)
    exit_code=$?

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # 元のディレクトリに戻る
    cd "$current_dir"

    echo ""
    echo "$output"

    # Claude Codeの出力をログに記録（詳細）
    if [[ -n "$output" ]]; then
        log "INFO" "Claude CLI出力 (${#output}文字):"
        echo "$output" | while IFS= read -r line; do
            # 空行はスキップ
            [[ -z "$line" ]] && continue
            log "INFO" "  | $line"
        done
    else
        log "WARN" "Claude CLI出力がありません"
    fi

    log "INFO" "Claude CLI実行完了: 終了コード=$exit_code, 所要時間=${elapsed}秒"

    if [[ $exit_code -eq 0 ]]; then
        # タスクを完了
        complete_task "$task_id" "success"
        log "INFO" "完了: [#$task_id] $task_desc (所要時間: ${elapsed}秒)"
        printf "%b" "${GREEN}✓ タスク完了: #$task_id${NC}\n"
        return 0
    elif [[ $exit_code -eq 142 ]] || [[ $exit_code -eq 124 ]]; then
        # タイムアウト（SIGALRMは142=128+14）
        local timeout_msg="Claude Codeが${task_timeout}秒でタイムアウトしました"
        fail_task "$task_id" "$timeout_msg"
        log "ERROR" "タイムアウト: [#$task_id] $timeout_msg"
        printf "%b" "${RED}✗ タスク失敗: #$task_id - ${timeout_msg}${NC}\n"
        printf "%b" "${YELLOW}  環境変数 CLAUDE_TIMEOUT または BASE_TIMEOUT でタイムアウト時間を変更できます${NC}\n"
        return 1
    else
        # タスクを失敗
        fail_task "$task_id" "Claude Code実行エラー (exit: $exit_code)"
        log "ERROR" "エラー: [#$task_id] Claude Code実行エラー (exit: $exit_code)"
        printf "%b" "${RED}✗ タスク失敗: #$task_id${NC}\n"
        return 1
    fi
}

# ==============================================================================
# メインループ
# ==============================================================================

run_agent_loop() {
    local agent="$1"
    local task_count=0
    local max_tasks=10  # 最大10タスク実行

    log "INFO" "エージェント起動: $agent"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  エージェント: $agent${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    while [[ $task_count -lt $max_tasks ]]; do
        # 次のタスクを取得
        local task_info=$(get_next_task "$agent")

        if [[ -z "$task_info" ]]; then
            printf "%b" "${YELLOW}実行可能なタスクがありません${NC}\n"
            break
        fi

        local task_id=$(echo "$task_info" | cut -f1)
        local task_desc=$(echo "$task_info" | cut -f2)
        local task_priority=$(echo "$task_info" | cut -f3)

        # タスクを開始
        start_task "$task_id"

        # タスクを実行
        if execute_task "$agent" "$task_id" "$task_desc"; then
            task_count=$((task_count + 1))
        else
            printf "%b" "${YELLOW}続行しますか？ (y/N):${NC} "
            read -r -n 1 response
            echo ""
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                break
            fi
        fi

        echo ""
        printf "%b" "${BLUE}次のタスクを確認中...${NC}\n"
        echo ""
        sleep 1
    done

    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}実行完了: ${task_count}個のタスク${NC}\n"
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    if [[ $task_count -gt 0 ]]; then
        log "INFO" "エージェント完了: $agent (${task_count}タスク実行)"
    else
        log "INFO" "エージェント終了: $agent (実行タスクなし)"
    fi
}

# ==============================================================================
# Watch モード（タスク待機＆自動実行）
# ==============================================================================

run_watch_mode() {
    local agent="$1"
    local worktree="${2:-}"

    log "INFO" "Watchモード起動: $agent (worktree: ${worktree:-none})"

    if [[ -n "$worktree" ]]; then
        local worktree_path="$SCRIPT_DIR/worktrees/$worktree"
        if [[ -d "$worktree_path" ]]; then
            cd "$worktree_path"
            log "INFO" "Worktree: $worktree_path"
        else
            log "ERROR" "Worktreeが見つかりません: $worktree_path"
            printf "%b" "${RED}Worktreeが見つかりません: $worktree${NC}\n"
            exit 1
        fi
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  Watch モード: $agent${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}タスクを待機中... (Ctrl+C で終了)${NC}\n"
    echo ""

    local last_task_count=0
    local check_interval=5

    while true; do
        # 未着手タスクをカウント
        local pending_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent and .status == "pending")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")

        # タスクが存在し、前回チェック時と数が異なる場合に実行
        if [[ "$pending_count" -gt 0 && "$pending_count" -ne "$last_task_count" ]]; then
            printf "%b" "${GREEN}新しいタスクを検出 (${pending_count}個)${NC}\n"
            run_agent_loop "$agent"
            # タスク実行後のpendingタスク数を再取得してlast_task_countを更新
            last_task_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent and .status == "pending")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
        fi

        sleep "$check_interval"
    done
}

# ==============================================================================
# ヘルプ表示
# ==============================================================================

show_help() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  Claude Code エージェント起動スクリプト${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    echo "使用方法: ./agent.sh <エージェント> [モード]"
    echo ""
    echo "エージェント:"
    echo "  ${CYAN}frontend${NC}      - フロントエンド開発"
    echo "  ${CYAN}backend${NC}       - バックエンド開発"
    echo "  ${CYAN}tests${NC}         - テスト作成・実行"
    echo "  ${CYAN}docs${NC}          - ドキュメント作成"
    echo ""
    echo "モード:"
    echo "  ${CYAN}(省略)${NC}         - タスクを実行して終了"
    echo "  ${CYAN}watch${NC}         - タスクを待機して自動実行（ループ）"
    echo "  ${CYAN}watch <worktree>${NC} - Worktreeでwatchモード"
    echo ""
    echo "例:"
    echo "  ./agent.sh frontend"
    echo "  ./agent.sh backend watch"
    echo "  ./agent.sh frontend worktree"
    echo ""
}

# ==============================================================================
# メイン処理
# ==============================================================================

AGENT_NAME="${1:-}"
AGENT_MODE="${2:-}"

# PIDファイルの作成
if [[ -n "$AGENT_NAME" && "$AGENT_NAME" != "help" && "$AGENT_NAME" != "--help" && "$AGENT_NAME" != "-h" ]]; then
    echo $$ > "$PIDS_DIR/${AGENT_NAME}.pid"
    
    # 基本情報のJSONを作成
    echo "{\"started_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"pid\": $$}" > "$PIDS_DIR/${AGENT_NAME}.json"
fi

case "$AGENT_NAME" in
    frontend|backend|tests|docs|planner|architect|reviewer|tester)
        if [[ "$AGENT_MODE" == "watch" ]]; then
            run_watch_mode "$AGENT_NAME"
        else
            run_agent_loop "$AGENT_NAME"
        fi
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        printf "%b" "${RED}エラー: 不明なエージェント '$1'${NC}\n"
        echo ""
        show_help
        exit 1
        ;;
esac
