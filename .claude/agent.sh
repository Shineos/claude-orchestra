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
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-600}"  # デフォルト10分

# ==============================================================================
# ログ関数
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # stdoutのみに出力（orchestratorがログファイルへのリダイレクトを担当）
    # 直接実行時も出力が表示されるため、teeは使用しない
    echo "[$timestamp] [$level] $message"
}

# ==============================================================================
# タスク管理関数
# ==============================================================================

# 契約ファイルを読み込み
load_contract() {
    local contract_path="$1"
    if [[ -n "$contract_path" && "$contract_path" != "null" && -f "$contract_path" ]]; then
        cat "$contract_path"
    fi
}

# ==============================================================================
# コンテキスト読み込み関数
# ==============================================================================

# ADRファイルを読み込み
load_adr() {
    local adr_id="$1"
    local adr_dir="$SCRIPT_DIR/context/architectural_decisions"

    # ADRファイルを検索
    for adr_file in "$adr_dir"/*.md; do
        [[ -f "$adr_file" ]] || continue
        [[ "$adr_file" == *TEMPLATE.md ]] && continue

        local filename=$(basename "$adr_file")
        local file_id=$(echo "$filename" | cut -d'-' -f1)

        if [[ "$file_id" == "$(printf "%03d" "$adr_id")" ]] || [[ "$file_id" == "$adr_id" ]]; then
            cat "$adr_file"
            return 0
        fi
    done

    return 1
}

# コーディング規約を読み込み
load_coding_conventions() {
    local conventions_file="$SCRIPT_DIR/context/coding_conventions.md"
    if [[ -f "$conventions_file" ]]; then
        cat "$conventions_file"
    fi
}

# 現在状態を読み込み
load_current_state() {
    local state_file="$SCRIPT_DIR/context/current_state.md"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    fi
}

# プロジェクト用語集を読み込み
load_glossary() {
    local glossary_file="$SCRIPT_DIR/context/project_glossary.md"
    if [[ -f "$glossary_file" ]]; then
        cat "$glossary_file"
    fi
}

# コンテキストを構築して出力
# タスクに関連するADR、コーディング規約、現在状態を統合
load_context() {
    local task_id="$1"

    # タスクの関連ADRを取得
    local related_adrs=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .related_adr[]? // empty' \
        "$TASKS_FILE" 2>/dev/null)

    local context=""
    local has_context=false

    # コーディング規約（常に読み込み）
    local conventions=$(load_coding_conventions)
    if [[ -n "$conventions" ]]; then
        context+="## プロジェクトのコーディング規約"$'\n\n'
        context+="$conventions"$'\n\n'
        has_context=true
    fi

    # 関連ADRを読み込み
    if [[ -n "$related_adrs" ]]; then
        context+="## 関連するアーキテクチャ決定記録 (ADR)"$'\n\n'
        while IFS= read -r adr_id; do
            [[ -z "$adr_id" ]] && continue
            local adr_content=$(load_adr "$adr_id")
            if [[ -n "$adr_content" ]]; then
                context+="### ADR #$adr_id"$'\n\n'
                context+="$adr_content"$'\n\n'
            fi
        done <<< "$related_adrs"
        has_context=true
    fi

    # 現在状態（最新情報のみを読み込み）
    local state=$(load_current_state)
    if [[ -n "$state" ]]; then
        context+="## プロジェクトの現在状態"$'\n\n'
        # 実装済み機能と技術スタックのみ抽出（簡略版）
        context+="<details>"$'\n'
        context+="<summary>現在状態を展開</summary>"$'\n\n'
        context+="$state"$'\n\n'
        context+="</details>"$'\n\n'
        has_context=true
    fi

    # 用語集が必要な場合のみ読み込み（プロンプトが長くなりすぎるため）
    # タスクdescriptionに専門用語が含まれる場合は別途判断

    if [[ "$has_context" == "true" ]]; then
        echo "$context"
    fi
}

# 検証ステップを実行
run_verification_steps() {
    local task_id="$1"

    # 検証ステップを取得
    local verification_steps=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .verification_steps[]?' \
        "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$verification_steps" ]]; then
        return 0  # 検証ステップなし = 成功
    fi

    log "INFO" "検証ステップを実行中..."

    while IFS= read -r step; do
        [[ -z "$step" ]] && continue
        log "INFO" "  実行: $step"

        if ! eval "$step" > /dev/null 2>&1; then
            log "ERROR" "検証ステップ失敗: $step"
            return 1
        fi
    done <<< "$verification_steps"

    log "INFO" "検証ステップ完了"
    return 0
}

# タスクステータスを更新
update_task_status() {
    local task_id="$1"
    local new_status="$2"

    local updated_tasks=$(jq --argjson id "$task_id" \
        --arg status "$new_status" \
        '(.tasks[] | select(.id == $id)) |= .status = $status' \
        "$TASKS_FILE")
    echo "$updated_tasks" > "$TASKS_FILE"
}

# エージェントの次のタスクを取得
get_next_task() {
    local agent="$1"
    if [[ -f "$TASKS_FILE" ]]; then
        # 依存関係が満たされた未着手タスクを取得
        local result=$(jq -r --arg agent "$agent" '
            .tasks as $all_tasks
            | .tasks
            | map(select(.agent == $agent and .status == "pending"))
            | map(select(
                .dependencies == null or
                (.dependencies | length) == 0 or
                (.dependencies | map(. as $dep_id | $all_tasks[] | select(.id == $dep_id) | .status == "completed") | all)
            ))
            | sort_by(.created_at)
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
# タスク実行
# ==============================================================================

execute_task() {
    local agent="$1"
    local task_id="$2"
    local task_desc="$3"
    local system_prompt=$(load_agent "$agent")

    # タスク情報を取得（拡張フィールド対応）
    local contract_path=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .contract // "null"' \
        "$TASKS_FILE" 2>/dev/null)

    local deliverables=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .deliverables[]? // empty' \
        "$TASKS_FILE" 2>/dev/null)

    local dod=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .definition_of_done[]? // empty' \
        "$TASKS_FILE" 2>/dev/null)

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク実行中${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}タスクID: ${NC}#$task_id\n"
    printf "%b" "${YELLOW}エージェント: ${NC}$agent\n"
    printf "%b" "${YELLOW}説明: ${NC}$task_desc\n"
    if [[ -n "$contract_path" && "$contract_path" != "null" ]]; then
        printf "%b" "${BLUE}契約: ${NC}$contract_path\n"
    fi
    echo ""
    printf "%b" "${BLUE}Claude Codeで実行中...${NC}\n"
    echo ""

    log "INFO" "開始: [#$task_id] $task_desc"

    # Claude CLIでタスクを実行（非対話モード）
    local prompt="${system_prompt}"$'\n\n'

    # コンテキスト情報を読み込み（ADR、コーディング規約、現在状態）
    local context=$(load_context "$task_id")
    if [[ -n "$context" ]]; then
        prompt+="## プロジェクトコンテキスト"$'\n\n'
        prompt+="以下は、このプロジェクトの重要な情報です。作業する前に理解してください。"$'\n\n'
        prompt+="$context"$'\n\n'
        prompt+="---"$'\n\n'
        log "INFO" "コンテキストを読み込みました"
    fi

    # 契約情報をプロンプトに追加
    if [[ -n "$contract_path" && "$contract_path" != "null" ]]; then
        local contract_content=$(load_contract "$contract_path")
        if [[ -n "$contract_content" ]]; then
            prompt+="## 契約仕様${contract_path}"$'\n\n'
            prompt+="$contract_content"$'\n\n'
            prompt+="上記の仕様に従って実装してください。"$'\n\n'
        fi
    fi

    # Deliverablesをプロンプトに追加
    if [[ -n "$deliverables" ]]; then
        prompt+="## 期待する成果物"$'\n'
        while IFS= read -r deliv; do
            [[ -n "$deliv" ]] && prompt+="  - $deliv"$'\n'
        done <<< "$deliverables"
        prompt+=$'\n'
    fi

    # 完了定義(DoD)をプロンプトに追加
    if [[ -n "$dod" ]]; then
        prompt+="## 完了基準"$'\n'
        while IFS= read -r criterion; do
            [[ -n "$criterion" ]] && prompt+="  - [ ] $criterion"$'\n'
        done <<< "$dod"
        prompt+=$'\n'
    fi

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
    log "INFO" "  タイムアウト設定: ${CLAUDE_TIMEOUT}秒"

    # Perlのalarm機能でタイムアウトを実装（macOSのtimeoutコマンドなし対応）
    # --verboseフラグで詳細ログ（思考プロセスなど）を出力
    output=$(perl -e "alarm $CLAUDE_TIMEOUT; exec @ARGV;" \
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
        # Pre-Review自動チェック
        local pre_review_script="$SCRIPT_DIR/pre-review-check.sh"
        if [[ -f "$pre_review_script" ]]; then
            log "INFO" "Pre-Reviewチェック実行中..."
            if bash "$pre_review_script" "$task_id" "$agent"; then
                # 自動チェック成功 -> review_neededに移行
                update_task_status "$task_id" "review_needed"
                log "INFO" "レビュー待ちに移行: [#$task_id]"
                printf "%b" "${BLUE}⏳ レビュー待ち: #$task_id${NC}\n"
                return 0
            else
                # 自動チェック失敗 -> rejectedに移行
                update_task_status "$task_id" "rejected"
                fail_task "$task_id" "Pre-Reviewチェック失敗"
                log "ERROR" "Pre-Reviewチェック失敗: [#$task_id]"
                printf "%b" "${RED}✗ Pre-Reviewチェック失敗: #$task_id${NC}\n"
                return 1
            fi
        fi

        # 検証ステップを実行
        if run_verification_steps "$task_id"; then
            # Pre-Reviewチェックがない場合は完了
            update_task_status "$task_id" "review_needed"
            log "INFO" "レビュー待ちに移行: [#$task_id]"
            printf "%b" "${BLUE}⏳ レビュー待ち: #$task_id${NC}\n"
            return 0
        else
            # 検証失敗 -> rejectedステータス
            update_task_status "$task_id" "rejected"
            fail_task "$task_id" "検証ステップ失敗"
            log "ERROR" "検証失敗: [#$task_id]"
            printf "%b" "${RED}✗ 検証ステップ失敗: #$task_id${NC}\n"
            return 1
        fi
    elif [[ $exit_code -eq 142 ]] || [[ $exit_code -eq 124 ]]; then
        # タイムアウト（SIGALRMは142=128+14）
        local timeout_msg="Claude Codeが${CLAUDE_TIMEOUT}秒でタイムアウトしました"
        update_task_status "$task_id" "rejected"
        fail_task "$task_id" "$timeout_msg"
        log "ERROR" "タイムアウト: [#$task_id] $timeout_msg"
        printf "%b" "${RED}✗ タスク失敗: #$task_id - ${timeout_msg}${NC}\n"
        printf "%b" "${YELLOW}  環境変数 CLAUDE_TIMEOUT でタイムアウト時間を変更できます（現在: ${CLAUDE_TIMEOUT}秒）${NC}\n"
        return 1
    else
        # タスクを失敗
        update_task_status "$task_id" "rejected"
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
    echo "  ${CYAN}architect${NC}     - システム設計・インターフェース契約"
    echo "  ${CYAN}frontend${NC}      - フロントエンド開発"
    echo "  ${CYAN}backend${NC}       - バックエンド開発"
    echo "  ${CYAN}reviewer${NC}      - コードレビュー・品質保証"
    echo "  ${CYAN}tests${NC}         - テスト作成・実行"
    echo "  ${CYAN}docs${NC}          - ドキュメント作成"
    echo ""
    echo "モード:"
    echo "  ${CYAN}(省略)${NC}         - タスクを実行して終了"
    echo "  ${CYAN}watch${NC}         - タスクを待機して自動実行（ループ）"
    echo "  ${CYAN}watch <worktree>${NC} - Worktreeでwatchモード"
    echo ""
    echo "例:"
    echo "  ./agent.sh architect"
    echo "  ./agent.sh frontend"
    echo "  ./agent.sh backend watch"
    echo "  ./agent.sh reviewer"
    echo ""
}

# ==============================================================================
# メイン処理
# ==============================================================================

AGENT_NAME="${1:-}"
AGENT_MODE="${2:-}"

case "$AGENT_NAME" in
    architect|frontend|backend|tests|docs|reviewer)
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
