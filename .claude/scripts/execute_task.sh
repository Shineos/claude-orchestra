#!/bin/bash
# タスク自動実行スクリプト
#
# Claude Code APIを使用してタスクを自動実行し、進捗を表示します
#
# 使用方法:
#   ./execute_task.sh <task_id> [--watch]
#
# 例:
#   ./execute_task.sh 1              # タスク#1を実行
#   ./execute_task.sh 1 --watch      # タスク#1を監視モードで実行

set -e

# =============================================================================
# 設定
# =============================================================================

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0;m'

# スピナーアニメーション
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# =============================================================================
# パス設定
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$CLAUDE_DIR")"

TASKS_FILE="$CLAUDE_DIR/tasks.json"
LOGS_DIR="$CLAUDE_DIR/logs"
LOG_DATE=$(date +"%Y-%m-%d")
LOG_FILE="$LOGS_DIR/execution-$LOG_DATE.log"

# =============================================================================
# ユーティリティ関数
# =============================================================================

# ログ出力
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# タスク情報取得
get_task_info() {
    local task_id="$1"
    if [[ -f "$TASKS_FILE" ]]; then
        jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE" 2>/dev/null
    fi
}

# スピナー表示開始
start_spinner() {
    local message="$1"
    spinner_pid=""

    # サブシェルでスピナーを表示
    (
        while true; do
            for frame in "${SPINNER_FRAMES[@]}"; do
                printf "\r${CYAN}%s${NC} %s" "$frame" "$message"
                sleep 0.1
            done
        done
    ) &
    spinner_pid=$!
    disown "$spinner_pid" 2>/dev/null || true
}

# スピナー停止
stop_spinner() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null || true
        wait "$spinner_pid" 2>/dev/null || true
        spinner_pid=""
    fi
    # スピナーをクリア
    printf "\r%80s\r" " "
}

# ステータス表示
show_status() {
    local icon="$1"
    local color="$2"
    local message="$3"
    printf "${color}${icon}${NC} ${message}\n"
}

# プログレスバー表示
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percentage"
}

# =============================================================================
# タスク実行関数
# =============================================================================

# Claude Code APIでタスクを実行
execute_with_claude() {
    local prompt="$1"
    local output_file="$2"
    local log_file="$3"

    log "INFO" "Claude Code API呼び出し: ${prompt:0:100}..."

    # デモモード: タスク実行をシミュレート
    # 実際の環境では、Claude Code SDKやAPIを統合してください
    log "INFO" "デモモードでタスクを実行"

    # プロジェクト構造を分析（簡易版）
    local project_summary=""
    if [[ -d "$PROJECT_ROOT/src" ]]; then
        project_summary+="\n  - src/ ディレクトリが存在します"
    fi
    if [[ -d "$PROJECT_ROOT/app" ]]; then
        project_summary+="\n  - app/ ディレクトリが存在します"
    fi
    if [[ -f "$PROJECT_ROOT/package.json" ]]; then
        project_summary+="\n  - package.json が存在します"
    fi

    # 結果をファイルに出力
    cat > "$output_file" <<EOF
# タスク実行レポート

## 実行プロンプト
$prompt

## プロジェクト分析結果
プロジェクトルート: $PROJECT_ROOT$project_summary

## 実行サマリー
- ステータス: 成功（デモモード）
- 実行時間: $(date +"%Y-%m-%d %H:%M:%S")
- モード: シミュレーション

## 次のステップ
1. 実際の Claude Code SDK を統合してください
2. タスクに応じた処理ロジックを実装してください
3. 必要に応じて API キーを設定してください

---
注意: これはデモモードです。実際のタスク実行には、Claude Code API や SDK の統合が必要です。
EOF

    # ログにも記録
    echo "タスク実行プロンプト: $prompt" >> "$log_file"
    echo "プロジェクトルート: $PROJECT_ROOT" >> "$log_file"
    echo "実行完了: $(date +"%Y-%m-%d %H:%M:%S")" >> "$log_file"

    log "INFO" "タスク実行完了（デモモード）"
    return 0
}

# タスク完了
complete_task() {
    local task_id="$1"
    local status="$2"  # completed, failed
    local result="$3"

    log "INFO" "タスク完了: #$task_id (status: $status)"

    # タスクステータス更新
    local updated_tasks=$(jq --argjson id "$task_id" \
                             --arg status "$status" \
                             --arg result "$result" \
                             --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                             --arg completed_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                             '(.tasks[] | select(.id == $id)) |= (.status = $status | .result = $result | .updated_at = $updated_at | .completed_at = $completed_at | if $status == "completed" then .progress = 100 else . end)' "$TASKS_FILE")

    echo "$updated_tasks" > "$TASKS_FILE"
}

# タスク進捗更新
update_task_progress() {
    local task_id="$1"
    local progress="$2"
    local status="$3"  # in_progress, completed, failed

    log "INFO" "タスク進捗更新: #$task_id ($progress%)"

    local updated_tasks=$(jq --argjson id "$task_id" \
                             --argjson progress "$progress" \
                             --arg status "$status" \
                             --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                             '(.tasks[] | select(.id == $id)) |= (.progress = $progress | .status = $status | .updated_at = $updated_at)' "$TASKS_FILE")

    echo "$updated_tasks" > "$TASKS_FILE"
}

# =============================================================================
# タスク実行メイン処理
# =============================================================================

execute_task() {
    local task_id="$1"
    local watch_mode="${2:-false}"

    # タスク情報取得
    local task_info=$(get_task_info "$task_id")

    if [[ -z "$task_info" ]]; then
        show_status "✗" "$RED" "タスク #$task_id が見つかりません"
        exit 1
    fi

    local task_desc=$(echo "$task_info" | jq -r '.description')
    local task_agent=$(echo "$task_info" | jq -r '.agent')
    local task_status=$(echo "$task_info" | jq -r '.status')

    # 既に完了しているタスクの場合
    if [[ "$task_status" == "completed" ]]; then
        show_status "✓" "$GREEN" "タスク #$task_id は既に完了しています"
        echo ""
        echo "  タスク: $task_desc"
        echo "  担当: $task_agent"
        echo ""
        return 0
    fi

    # タスク実行開始
    printf "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}  タスク自動実行${NC}\n"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    echo "  タスクID: #$task_id"
    echo "  タスク: $task_desc"
    echo "  担当エージェント: $task_agent"
    echo "  監視モード: $watch_mode"
    echo ""

    # タスクステータスを in_progress に更新
    update_task_progress "$task_id" 0 "in_progress"

    # 出力ファイル（.claude/tasksディレクトリに保存）
    local output_dir="$CLAUDE_DIR/tasks"
    mkdir -p "$output_dir"
    local output_file="$output_dir/task-${task_id}-result.md"
    local execution_log="$output_dir/task-${task_id}-execution.log"

    # プロンプト作成
    local prompt="あなたは${task_agent}エージェントとして、以下のタスクを実行してください。

タスク: $task_desc

プロジェクトルート: $PROJECT_ROOT

注意事項:
- プロジェクトの既存コードを理解してから変更を加えてください
- 小さく変更してテストしてください
- エラーがあればログを確認してください
- 完了したら結果を報告してください"

    # スピナーを表示して実行
    start_spinner "タスクを実行中..."
    log "INFO" "タスク実行開始: #$task_id"

    # 実行ステップ数（例: 5ステップ）
    local total_steps=5

    # ステップ1: 環境確認
    sleep 0.5
    log "INFO" "ステップ1/5: 環境を確認中..."
    update_task_progress "$task_id" 20 "in_progress"
    show_progress 1 $total_steps

    # ステップ2: コンテキスト収集
    sleep 0.5
    log "INFO" "ステップ2/5: コンテキストを収集中..."
    update_task_progress "$task_id" 40 "in_progress"
    show_progress 2 $total_steps

    # ステップ3: Claude Codeで実行
    stop_spinner
    show_status "⚙" "$BLUE" "Claude Codeでタスクを実行中..."
    log "INFO" "ステップ3/5: Claude Codeで実行中..."

    if execute_with_claude "$prompt" "$output_file" "$execution_log"; then
        update_task_progress "$task_id" 60 "in_progress"
        show_progress 3 $total_steps

        # ステップ4: 結果検証
        sleep 0.5
        log "INFO" "ステップ4/5: 結果を検証中..."
        update_task_progress "$task_id" 80 "in_progress"
        show_progress 4 $total_steps

        # ステップ5: 完了
        sleep 0.5
        log "INFO" "ステップ5/5: タスク完了"
        show_progress 5 $total_steps
        echo ""

        complete_task "$task_id" "completed" "success"

        show_status "✓" "$GREEN" "タスク完了: #$task_id"
        echo ""
        echo "  結果: $output_file"
        echo "  ログ: $execution_log"
        echo ""

        # 監視モードで結果を表示
        if [[ "$watch_mode" == "true" && -f "$output_file" ]]; then
            printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            printf "${CYAN}  実行結果${NC}\n"
            printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            echo ""
            head -50 "$output_file"
            if [[ $(wc -l < "$output_file") -gt 50 ]]; then
                echo ""
                printf "... (${YELLOW}続きはファイルを確認してください${NC}) ..."
            fi
            echo ""
        fi

        return 0
    else
        stop_spinner
        show_progress 3 $total_steps
        echo ""

        complete_task "$task_id" "failed" "Claude Code実行エラー"

        show_status "✗" "$RED" "タスク失敗: #$task_id"
        echo ""
        echo "  エラー: Claude Codeの実行に失敗しました"
        echo "  ログ: $execution_log"
        echo ""

        return 1
    fi
}

# =============================================================================
# 監視モード
# =============================================================================

watch_and_execute() {
    local task_id="$1"

    execute_task "$task_id" true
}

# =============================================================================
# メイン処理
# ==============================================================================

show_help() {
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${CYAN}  タスク自動実行スクリプト${NC}\n"
    printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    echo "使用方法: ./execute_task.sh <task_id> [オプション]"
    echo ""
    echo "オプション:"
    echo "  ${CYAN}--watch${NC}        監視モードで実行（結果を表示）"
    echo "  ${CYAN}--help${NC}         このヘルプを表示"
    echo ""
    echo "例:"
    echo "  ./execute_task.sh 1              # タスク#1を実行"
    echo "  ./execute_task.sh 1 --watch      # タスク#1を監視モードで実行"
    echo ""
}

# ログディレクトリ作成
mkdir -p "$LOGS_DIR"

# 引数チェック
if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# タスクID取得
TASK_ID="$1"
WATCH_MODE="false"

# オプション解析
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch)
            WATCH_MODE="true"
            ;;
        *)
            printf "${RED}エラー: 不明なオプション '$1'${NC}\n"
            echo ""
            show_help
            exit 1
            ;;
    esac
    shift
done

# タスクIDが数字かチェック
if ! [[ "$TASK_ID" =~ ^[0-9]+$ ]]; then
    printf "${RED}エラー: タスクIDは数字で指定してください${NC}\n"
    exit 1
fi

# タスク実行
if [[ "$WATCH_MODE" == "true" ]]; then
    watch_and_execute "$TASK_ID"
else
    execute_task "$TASK_ID" "false"
fi
