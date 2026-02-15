#!/bin/bash
# Orchestrator Agent - タスク管理・モニタリング機能
#
# 使用方法:
#   orchestrator.sh status              # 全タスクの状況表示
#   orchestrator.sh add <task> [agent]  # タスク追加（エージェント省略で自動振り分け）
#   orchestrator.sh start <task_id>     # タスク開始
#   orchestrator.sh complete <task_id>  # タスク完了
#   orchestrator.sh fail <task_id>      # タスク失敗
#   orchestrator.sh monitor             # リアルタイムモニタリング
#   orchestrator.sh launch              # タスクに応じてエージェントを自動起動
#   orchestrator.sh worktree            # Git Worktree 操作

set -e

# 色設定（ANSI-C quotingでエスケープシーケンスを正しく解釈）
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m'

# プロジェクトルートディレクトリ
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR は .claude/scripts を指すので、その親が CLAUDE_DIR になる
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
# CLAUDE_DIR の親が PROJECT_ROOT
PROJECT_ROOT="$(dirname "$CLAUDE_DIR")"

# タスクデータ保存場所
TASKS_FILE="$CLAUDE_DIR/tasks.json"
TASKS_DIR="$CLAUDE_DIR/tasks"

# Worktree ディレクトリ
WORKTREES_DIR="$PROJECT_ROOT/.claude/worktrees"

# エージェント起動スクリプト
AGENT_SCRIPT="$CLAUDE_DIR/agent.sh"

# デフォルトタイムアウト設定（秒）
CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-1200}"

# Worktree モード設定
USE_WORKTREE="${USE_WORKTREE:-false}"

# ==============================================================================
# ログ機能
# ==============================================================================

# ログディレクトリ
LOGS_DIR="$CLAUDE_DIR/logs"

# ログファイル（日付別）
LOG_DATE=$(date +"%Y-%m-%d")
ORCH_LOG_FILE="$LOGS_DIR/orchestrator-$LOG_DATE.log"

# ログディレクトリ作成
mkdir -p "$LOGS_DIR"

# エージェント名の先頭を大文字にするヘルパー関数
capitalize_agent() {
    case "$1" in
        architect) echo "Architect" ;;
        frontend) echo "Frontend" ;;
        backend) echo "Backend" ;;
        tests) echo "Tests" ;;
        docs) echo "Docs" ;;
        reviewer) echo "Reviewer" ;;
        orchestrator) echo "Orchestrator" ;;
        *) echo "$1" ;;
    esac
}

# ログ出力関数
orch_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$ORCH_LOG_FILE"
}

# ログローテーション
orch_rotate_logs() {
    if [[ -d "$LOGS_DIR" ]]; then
        # 7日以上前のログを圧縮
        find "$LOGS_DIR" -name "orchestrator-*.log" -mtime +7 -exec gzip -q {} \; 2>/dev/null || true
        # 30日以上前の圧縮ログを削除
        find "$LOGS_DIR" -name "orchestrator-*.log.gz" -mtime +30 -delete 2>/dev/null || true
        # agent.log も同様に処理
        find "$LOGS_DIR" -name "agent-*.log" -mtime +7 -exec gzip -q {} \; 2>/dev/null || true
        find "$LOGS_DIR" -name "agent-*.log.gz" -mtime +30 -delete 2>/dev/null || true
    fi
}

# ==============================================================================
# ロックファイル機構
# ==============================================================================

# タスクリーファイル排他制御をロード
TASK_LOCK_SCRIPT="$SCRIPT_DIR/task-lock.sh"
if [[ -f "$TASK_LOCK_SCRIPT" ]]; then
    source "$TASK_LOCK_SCRIPT"
else
    # スクリプトがない場合はダミー関数を定義
    acquire_lock() { return 0; }
    release_lock() { return 0; }
    show_lock_status() { echo "ロック機能: 利用不可"; }
fi

# ==============================================================================
# 初期化関数
# ==============================================================================

# Staleタスクのクリーンアップ（放置されたin_progressタスクをpendingに戻す）
cleanup_stale_tasks() {
    local stale_threshold_hours="${STALE_THRESHOLD_HOURS:-1}"
    local stale_threshold_seconds=$((stale_threshold_hours * 3600))
    local current_time=$(date +%s)
    local cleaned_count=0

    if [[ ! -f "$TASKS_FILE" ]]; then
        return 0
    fi

    # in_progressタスクをチェック
    local stale_tasks=$(jq -r --argjson current_time "$current_time" --argjson threshold "$stale_threshold_seconds" '
        .tasks
        | to_entries
        | map(select(.value.status == "in_progress" and .value.started_at != null))
        | map(select(($current_time - (.value.started_at | fromdateiso8601)) > $threshold))
        | from_entries
        | keys[]
    ' "$TASKS_FILE" 2>/dev/null || echo "")

    if [[ -n "$stale_tasks" ]]; then
        for idx in $stale_tasks; do
            local task_id=$(jq -r ".tasks[$idx].id" "$TASKS_FILE")
            orch_log "WARN" "Stale task detected: #$task_id (resetting to pending)"
            ((cleaned_count++))
        done

        # 一括でステータスを更新
        local updated_tasks=$(jq --argjson current_time "$current_time" --argjson threshold "$stale_threshold_seconds" '
            .tasks |= map(
                if .status == "in_progress" and .started_at != null and (($current_time - (.started_at | fromdateiso8601)) > $threshold) then
                    .status = "pending" | .started_at = null | .notes += [{"text": "Auto-recovered from stale state", "timestamp": (now | todateiso8601)}]
                else
                    .
                end
            )
        ' "$TASKS_FILE")

        echo "$updated_tasks" > "$TASKS_FILE"

        if [[ $cleaned_count -gt 0 ]]; then
            orch_log "INFO" "Cleaned up $cleaned_count stale task(s)"
        fi
    fi
}

# 初期化関数
init_tasks() {
    mkdir -p "$TASKS_DIR"
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo '{"tasks": [], "last_id": 0}' > "$TASKS_FILE"
    fi
    # ログローテーション実行
    orch_rotate_logs
    # Staleタスクのクリーンアップ
    cleanup_stale_tasks
}

# タスクID生成
generate_task_id() {
    local last_id=$(jq -r '.last_id' "$TASKS_FILE")
    echo $((last_id + 1))
}

# ==============================================================================
# 自動振り分け機能
# ==============================================================================

# タスク内容からエージェントを自動判定
detect_agent() {
    local task_desc="$1"
    task_desc=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')

    # キーワードパターン定義
    local architect_keywords=(
        "api" "仕様" "spec" "契約" "contract" "スキーマ" "schema"
        "設計" "design" "アーキテクチャ" "architecture"
        "インターフェース" "interface" "型定義" "type"
        "openapi" "swagger" "yaml"
    )

    local frontend_keywords=(
        "ui" "画面" "界面" "フロント" "frontend" "コンポーネント" "component"
        "スタイル" "style" "css" "レスポンシブ" "responsive" "アニメーション" "animation"
        "ボタン" "button" "フォーム" "form" "入力" "input" "表示" "display"
        "モーダル" "modal" "ダイアログ" "dialog" "ナビゲーション" "navigation"
        "レイアウト" "layout" "デザイン" "design" "ビュー" "view"
        "tsx" "jsx" "vue" "svelte" "react"
    )

    local backend_keywords=(
        "サーバー" "server" "バックエンド" "backend" "データベース" "database"
        "認証" "auth" "ログイン" "login" "サインイン" "signin" "登録" "register"
        "セッション" "session" "トークン" "token" "jwt" "パスワード" "password"
        "コントローラー" "controller" "モデル" "model"
        "マイグレーション" "migration" "クエリ" "query" "sql" "nosql"
        "エンドポイント" "endpoint" "ルート" "route" "ミドルウェア" "middleware"
        "バリデーション" "validation" "リクエスト" "request" "レスポンス" "response"
    )

    local tests_keywords=(
        "テスト" "test" "試験" "スペック" "spec" "アサーション" "assertion"
        "モック" "mock" "スタブ" "stub" "カバレッジ" "coverage"
        "単体テスト" "unit test" "結合テスト" "integration test"
        "e2e" "エンドツーエンド" "cypress" "playwright" "jest" "vitest"
    )

    local docs_keywords=(
        "ドキュメント" "document" "ドキュメンテーション" "documentation"
        "readme" "api doc" "仕様書" "specification" "コメント" "comment"
        "説明" "explain" "マニュアル" "manual" "ガイド" "guide"
    )

    # Architect チェック（最優先）
    for keyword in "${architect_keywords[@]}"; do
        if [[ "$task_desc" == *"$keyword"* ]]; then
            echo "architect"
            return 0
        fi
    done

    # Frontend チェック
    for keyword in "${frontend_keywords[@]}"; do
        if [[ "$task_desc" == *"$keyword"* ]]; then
            echo "frontend"
            return 0
        fi
    done

    # Backend チェック
    for keyword in "${backend_keywords[@]}"; do
        if [[ "$task_desc" == *"$keyword"* ]]; then
            echo "backend"
            return 0
        fi
    done

    # Tests チェック
    for keyword in "${tests_keywords[@]}"; do
        if [[ "$task_desc" == *"$keyword"* ]]; then
            echo "tests"
            return 0
        fi
    done

    # Docs チェック
    for keyword in "${docs_keywords[@]}"; do
        if [[ "$task_desc" == *"$keyword"* ]]; then
            echo "docs"
            return 0
        fi
    done

    # デフォルトは Orchestrator
    echo "orchestrator"
}

# ==============================================================================
# AI タスク分解機能
# ==============================================================================

# AIでタスクを分解（Claude CLIを直接使用）
decompose_task_ai() {
    local task_desc="$1"
    local feedback="${2:-}"

    orch_log "INFO" "AI分解開始: $task_desc"

    # Claudeコマンドが利用可能かチェック
    if ! command -v claude &> /dev/null; then
        orch_log "WARN" "claude コマンドが見つかりません。Claude Code をインストールしてください"
        return 1
    fi

    # システムプロンプトを読み込み
    local prompt_file="$SCRIPT_DIR/../prompts/decompose_task.txt"
    if [[ ! -f "$prompt_file" ]]; then
        orch_log "WARN" "プロンプトファイルが見つかりません: $prompt_file"
        return 1
    fi

    local system_prompt
    system_prompt=$(cat "$prompt_file")

    # 入力プロンプトを作成
    local input_prompt="タスク: ${task_desc}"
    if [[ -n "$feedback" ]]; then
        input_prompt="${input_prompt}"$'\n\n'"前回のフィードバック: ${feedback}"
    fi

    # Claude CLIを直接呼び出し
    local cli_output
    cli_output=$(claude -p --system-prompt "$system_prompt" --output-format text "$input_prompt" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        orch_log "ERROR" "Claude CLI 実行エラー: $cli_output"
        return 1
    fi

    # JSONを抽出
    local result_json="$cli_output"

    # マークダウンコードブロックからJSONを抽出
    if echo "$result_json" | grep -q '```'; then
        result_json=$(echo "$result_json" | sed -n '/```/,/```/p' | sed '1d;$d' | sed 's/^json//')
    fi

    # 先頭の{から最後の}までを抽出
    if echo "$result_json" | grep -q '{'; then
        result_json=$(echo "$result_json" | sed -n '/^{/,/^}/p')
    fi

    # 結果を検証
    if ! echo "$result_json" | jq empty 2>/dev/null; then
        orch_log "ERROR" "AI分解が有効なJSONを返しませんでした: $result_json"
        return 1
    fi

    # エラーチェック
    local error=$(echo "$result_json" | jq -r '.error // empty')
    if [[ -n "$error" && "$error" != "null" ]]; then
        orch_log "ERROR" "AI分解エラー ($error): $(echo "$result_json" | jq -r '.message // empty')"
        return 1
    fi

    # 成功 - 結果を表示（デバッグ用）
    local subtask_count=$(echo "$result_json" | jq -r '.subtasks | length // 0')
    orch_log "INFO" "AI分解成功: ${subtask_count} 個のサブタスク"

    echo "$result_json"
    return 0
}

# 分解結果を検証
validate_decomposition() {
    local json="$1"

    # JSON形式チェック
    if ! echo "$json" | jq empty 2>/dev/null; then
        echo "invalid_json"
        return 1
    fi

    # subtasksフィールドチェック
    local has_subtasks=$(echo "$json" | jq 'has("subtasks")')
    if [[ "$has_subtasks" != "true" ]]; then
        echo "missing_subtasks"
        return 1
    fi

    # サブタスク数チェック
    local subtask_count=$(echo "$json" | jq '.subtasks | length')
    if [[ "$subtask_count" -eq 0 ]]; then
        echo "no_subtasks"
        return 1
    fi

    # 各サブタスクの必須フィールドチェック
    local missing_fields=$(echo "$json" | jq '[.subtasks[] | select(.description == null or .agent == null)] | length')
    if [[ "$missing_fields" -gt 0 ]]; then
        echo "missing_fields"
        return 1
    fi

    # エージェント名の検証
    local invalid_agents=$(echo "$json" | jq '[.subtasks[].agent] - ["architect", "frontend", "backend", "tests", "docs", "reviewer", "orchestrator"] | unique | length')
    if [[ "$invalid_agents" -gt 0 ]]; then
        echo "invalid_agent"
        return 1
    fi

    echo "valid"
    return 0
}

# 分解プランを表示して確認
confirm_decomposition() {
    local original_task="$1"
    local decomposition_json="$2"
    local attempt="${3:-1}"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク分解プラン${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}元のタスク:${NC}\n"
    echo "  $original_task"
    echo ""

    # サブタスクを表示
    local subtask_count=$(echo "$decomposition_json" | jq '.subtasks | length')
    printf "%b" "${GREEN}提案されたサブタスク (${subtask_count}個):${NC}\n"
    echo ""

    local index=1
    while IFS= read -r subtask; do
        local desc=$(echo "$subtask" | jq -r '.description')
        local agent=$(echo "$subtask" | jq -r '.agent')
        local rationale=$(echo "$subtask" | jq -r '.rationale // empty')
        local deps=$(echo "$subtask" | jq -r '.dependencies // [] | join(", ")')

        # エージェント別の色
        local agent_color=""
        case "$agent" in
            "frontend") agent_color="$BLUE" ;;
            "backend") agent_color="$GREEN" ;;
            "tests") agent_color="$YELLOW" ;;
            "docs") agent_color="$MAGENTA" ;;
            *) agent_color="$CYAN" ;;
        esac

        printf "%b" "${CYAN}[${index}]${NC} ${desc}\n"
        printf "%b" "    担当: ${agent_color}$(capitalize_agent "$agent")${NC}\n"
        if [[ -n "$rationale" ]]; then
            printf "%b" "    理由: ${rationale}\n"
        fi
        if [[ -n "$deps" ]]; then
            printf "%b" "    依存: [${deps}]\n"
            printf "%b" "    ${YELLOW}※ [0,1]は「0番目と1番目のタスク（1番目と2番目）」を意味します${NC}\n"
        fi
        echo ""
        index=$((index + 1))
    done < <(echo "$decomposition_json" | jq -c '.subtasks[]')

    # 確認を求める
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${YELLOW}このプランで進めますか？${NC}\n"
    echo ""
    printf "%b" "  ${GREEN}Y${NC} - このプランを承認\n"
    printf "%b" "  ${YELLOW}N${NC} - 拒否して再分解\n"
    printf "%b" "  ${CYAN}E${NC} - 手動で編集\n"
    printf "%b" "  ${RED}Q${NC} - キャンセル\n"
    echo ""
    printf "%b" "${YELLOW}選択:${NC} "

    # 自動確認モードチェック
    if [[ "${ORCH_AUTO_CONFIRM:-}" == "yes" ]]; then
        printf "%b" "${GREEN}Y${NC} (auto-confirm)\n"
        echo ""
        return 0
    fi

    # read -n 1はターミナルバッファと干渉するため、通常のreadで1行読んで最初の文字を取得
    read -r response < /dev/tty
    response="${response:0:1}"  # 最初の1文字のみ取得

    echo ""
    echo ""

    case "$response" in
        [Yy])
            return 0  # 承認
            ;;
        [Nn])
            if [[ $attempt -lt 3 ]]; then
                return 1  # 再分解
            else
                printf "%b" "${RED}最大再試行回数に達しました。ルールベースにフォールバックします。${NC}\n"
                return 2  # フォールバック
            fi
            ;;
        [Ee])
            return 3  # 編集モード
            ;;
        [Qq])
            return 4  # キャンセル
            ;;
        *)
            printf "%b" "${RED}無効な選択です。もう一度お試しください。${NC}\n"
            return 1
            ;;
    esac
}

# ユーザーフィードバックを収集
collect_feedback() {
    local original_plan="$1"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  フィードバック収集${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}どのように改善すればよいですか？${NC}\n"
    echo ""
    echo "  1. サブタスクを追加する"
    echo "  2. サブタスクを削除する"
    echo "  3. エージェントの割り当てを変更する"
    echo "  4. サブタスクの説明を変更する"
    echo "  5. 自由形式のフィードバック"
    echo ""
    printf "%b" "${YELLOW}選択:${NC} "

    # 自動確認モードチェック
    if [[ "${ORCH_AUTO_CONFIRM:-}" == "yes" ]]; then
        printf "%b" "${GREEN}Y${NC} (auto-confirm - フィードバックをスキップ)\n"
        echo ""
        return 1  # フィードバックなしで再分解
    fi

    read -r choice < /dev/tty
    echo ""

    local feedback=""

    case "$choice" in
        1)
            echo "追加したいサブタスクの説明を入力してください:"
            read -r feedback < /dev/tty
            feedback="action: add_subtask, description: $feedback"
            ;;
        2)
            echo "削除したいサブタスク番号を入力してください:"
            read -r idx < /dev/tty
            feedback="action: remove_subtask, index: $idx"
            ;;
        3)
            echo "変更したいサブタスク番号を入力してください:"
            read -r idx < /dev/tty
            echo "新しいエージェントを入力してください (frontend/backend/tests/docs):"
            read -r agent < /dev/tty
            feedback="action: change_agent, index: $idx, new_agent: $agent"
            ;;
        4)
            echo "変更したいサブタスク番号を入力してください:"
            read -r idx < /dev/tty
            echo "新しい説明を入力してください:"
            read -r desc < /dev/tty
            feedback="action: modify_description, index: $idx, new_description: $desc"
            ;;
        5)
            echo "自由形式のフィードバックを入力してください:"
            read -r feedback < /dev/tty
            feedback="action: freeform, feedback: $feedback"
            ;;
        *)
            feedback="action: retry_with_different_approach"
            ;;
    esac

    echo "$feedback"
}

# 分解結果を手動編集
edit_decomposition() {
    local decomposition_json="$1"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  手動編集モード${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}現在の分解結果:${NC}\n"
    echo ""
    echo "$decomposition_json" | jq '.'
    echo ""
    printf "%b" "${YELLOW}編集手順:${NC}\n"
    echo "  1. 上記のJSONをコピーしてエディタで編集してください"
    echo "  2. 編集したJSONを貼り付けてEnterを押してください"
    echo "  3. 空行を入力すると編集完了です"
    echo ""
    printf "%b" "${YELLOW}編集後のJSON:${NC}\n"

    local edited_json=""
    local line
    # TTYが利用可能な場合はTTYから、それ以外の場合はstdinから読み取る
    if [[ -t 0 ]]; then
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                break
            fi
            edited_json+="$line"$'\n'
        done
    else
        # /dev/ttyから読み取る（コマンド置換内でも動作するように）
        while IFS= read -r line < /dev/tty; do
            if [[ -z "$line" ]]; then
                break
            fi
            edited_json+="$line"$'\n'
        done
    fi

    # 検証
    local validation=$(validate_decomposition "$edited_json")
    if [[ "$validation" != "valid" ]]; then
        printf "%b" "${RED}編集内容が無効です (${validation})${NC}\n"
        return 1
    fi

    echo "$edited_json"
    return 0
}

# ==============================================================================
# タスク分解機能
# ==============================================================================

# タスクを複数のサブタスクに分解（AI優先、ルールベースフォールバック）
decompose_task() {
    local task_desc="$1"
    local use_ai="${USE_AI:-true}"

    # AI分解を試みる
    if [[ "$use_ai" == "true" ]]; then
        local ai_result
        ai_result=$(decompose_task_ai "$task_desc" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            # AI成功 - JSONを既存形式に変換
            # 既存形式: "description" "agent" の交互のリスト
            local subtasks=()
            while IFS= read -r subtask_json; do
                local desc=$(echo "$subtask_json" | jq -r '.description')
                local agent=$(echo "$subtask_json" | jq -r '.agent')
                subtasks+=("$desc" "$agent")
            done < <(echo "$ai_result" | jq -c '.subtasks[]')

            printf '%s\n' "${subtasks[@]}"
            return 0
        fi

        # AI失敗 - ログ記録してルールベースにフォールバック
        orch_log "WARN" "AI分解失敗、ルールベースにフォールバック: $ai_result"
    fi

    # ルールベース分解にフォールバック
    decompose_task_rules "$task_desc"
}

# タスクを複数のサブタスクに分解（ルールベース）
decompose_task_rules() {
    local task_desc="$1"
    local detected_agent=$(detect_agent "$task_desc")
    local subtasks=()

    task_desc=$(echo "$task_desc" | tr '[:upper:]' '[:lower:]')

    # 機能ベースの分解パターン
    if [[ "$task_desc" == *"認証"* ]] || [[ "$task_desc" == *"ログイン"* ]] || [[ "$task_desc" == *"auth"* ]] || [[ "$task_desc" == *"login"* ]]; then
        subtasks+=("ログインフォームのUI実装" "frontend")
        subtasks+=("認証APIの実装（POST /api/auth/login）" "backend")
        subtasks+=("セッション管理（JWT/Cookie）" "backend")
        subtasks+=("認証機能の単体テスト" "tests")
        subtasks+=("ログイン機能の結合テスト" "tests")
        subtasks+=("認証APIドキュメントの作成" "docs")

    elif [[ "$task_desc" == *"ユーザー登録"* ]] || [[ "$task_desc" == *"サインアップ"* ]] || [[ "$task_desc" == *"register"* ]] || [[ "$task_desc" == *"signup"* ]]; then
        subtasks+=("登録フォームのUI実装" "frontend")
        subtasks+=("ユーザー登録APIの実装" "backend")
        subtasks+=("メール確認機能の実装" "backend")
        subtasks+=("登録機能のテスト作成" "tests")
        subtasks+=("登録フローのドキュメント作成" "docs")

    elif [[ "$task_desc" == *"データベース"* ]] || [[ "$task_desc" == *"database"* ]] || [[ "$task_desc" == *"db"* ]]; then
        subtasks+=("データベーススキーマ設計" "backend")
        subtasks+=("マイグレーションファイル作成" "backend")
        subtasks+=("モデル定義の実装" "backend")
        subtasks+=("シーダー（初期データ）作成" "backend")
        subtasks+=("データベース設定のドキュメント作成" "docs")

    elif [[ "$task_desc" == *"api"* ]] || [[ "$task_desc" == *"エンドポイント"* ]]; then
        subtasks+=("API仕様の定義" "backend")
        subtasks+=("APIエンドポイントの実装" "backend")
        subtasks+=("リクエストバリデーション" "backend")
        subtasks+=("APIテストの作成" "tests")
        subtasks+=("APIドキュメントの作成" "docs")

    elif [[ "$task_desc" == *"ui"* ]] || [[ "$task_desc" == *"画面"* ]] || [[ "$task_desc" == *"コンポーネント"* ]]; then
        subtasks+=("コンポーネント設計" "frontend")
        subtasks+=("コンポーネント実装" "frontend")
        subtasks+=("スタイリング実装" "frontend")
        subtasks+=("レスポンシブ対応" "frontend")
        subtasks+=("コンポーネントのテスト作成" "tests")

    elif [[ "$task_desc" == *"テスト"* ]] || [[ "$task_desc" == *"test"* ]]; then
        # テスト関連は分解しない（Tests エージェント単体で対応）
        subtasks+=("$task_desc" "tests")

    elif [[ "$task_desc" == *"ドキュメント"* ]] || [[ "$task_desc" == *"document"* ]] || [[ "$task_desc" == *"readme"* ]]; then
        # ドキュメント関連は分解しない（Docs エージェント単体で対応）
        subtasks+=("$task_desc" "docs")

    else
        # デフォルト: 検出されたエージェントにそのまま割り当て
        subtasks+=("$task_desc" "$detected_agent")
    fi

    # 結果を返す
    printf '%s\n' "${subtasks[@]}"
}

# タスク追加（AI-powered エージェント自動判定・分解）
add_task_auto() {
    local task_desc="$1"
    local priority="${2:-normal}"
    local use_ai="${USE_AI:-true}"

    init_tasks

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク自動振り分け (AI Mode: ${use_ai})${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${CYAN}元のタスク:${NC} $task_desc"
    echo ""
    echo ""

    local decomposition_json=""
    local attempt=1
    local max_attempts=3
    local confirmed=false
    local use_rules_fallback=false

    # AIが無効な場合はルールベースを優先
    if [[ "$use_ai" == "false" ]]; then
        use_rules_fallback=true
    fi

    # AI分解と確認ループ
    while [[ $attempt -le $max_attempts && "$confirmed" == "false" ]]; do
        # AI分解を実行
        if [[ $attempt -eq 1 && "$use_ai" == "true" ]]; then
            printf "%b" "${BLUE}AIでタスクを分析中...${NC}\n"
            local ai_result
            ai_result=$(decompose_task_ai "$task_desc" 2>&1)
            local ai_exit=$?

            if [[ $ai_exit -eq 0 ]]; then
                # AI成功 - JSON形式で取得
                decomposition_json="$ai_result"
            else
                # AI失敗 - ルールベースにフォールバック
                printf "%b" "${YELLOW}AI分解に失敗しました。ルールベースを使用します...${NC}\n"
                use_rules_fallback=true
            fi
        elif [[ "$use_rules_fallback" == "true" ]]; then
            # ルールベース分解
            local subtasks=()
            while IFS= read -r line; do
                subtasks+=("$line")
            done < <(decompose_task_rules "$task_desc")

            # ルールベース結果をJSON形式に変換
            decomposition_json=$(subtasks_array_to_json "${subtasks[@]}")
        else
            # 再分解
            printf "%b" "${YELLOW}再分解中... (試行 ${attempt}/${max_attempts})${NC}\n"
            local feedback="${feedback:-}"
            local ai_result
            ai_result=$(decompose_task_ai "$task_desc" "$feedback" 2>&1)

            if [[ $? -eq 0 ]]; then
                decomposition_json="$ai_result"
            else
                # 失敗したらルールベースに
                use_rules_fallback=true
                local subtasks=()
                while IFS= read -r line; do
                    subtasks+=("$line")
                done < <(decompose_task_rules "$task_desc")
                decomposition_json=$(subtasks_array_to_json "${subtasks[@]}")
            fi
        fi

        # 分解結果を確認
        # set -eが有効なため、一時的に無効化して戻り値を取得
        # サブシェルを使用しない方法に変更
        set +e
        confirm_decomposition "$task_desc" "$decomposition_json" "$attempt"
        local confirm_result=$?
        set -e

        case $confirm_result in
            0)  # 承認
                confirmed=true
                ;;
            1)  # 再分解
                if [[ $attempt -lt $max_attempts ]]; then
                    feedback=$(collect_feedback "$decomposition_json")
                    attempt=$((attempt + 1))
                    echo ""
                    printf "%b" "${CYAN}フィードバックを反映して再分解します...${NC}\n"
                    echo ""
                else
                    printf "%b" "${RED}最大再試行回数に達しました。${NC}\n"
                    confirmed=true  # 現在のプランで続行
                fi
                ;;
            2)  # フォールバック
                printf "%b" "${YELLOW}ルールベース分解を使用します...${NC}\n"
                use_rules_fallback=true
                local subtasks=()
                while IFS= read -r line; do
                    subtasks+=("$line")
                done < <(decompose_task_rules "$task_desc")
                decomposition_json=$(subtasks_array_to_json "${subtasks[@]}")
                confirmed=true
                ;;
            3)  # 編集（JSON出力）
                # JSONファイルを出力して終了
                local json_file="$CLAUDE_DIR/decomposition.json"
                echo "$decomposition_json" | jq '.' > "$json_file"

                echo ""
                printf "%b" "${CYAN}\"${json_file}\"ファイルを手動で編集してください。${NC}\n"
                printf "%b" "${CYAN}編集後、\`${GREEN}orch load ${json_file}${CYAN}\`${NC} コマンド実行してください\n"
                echo ""

                return 0
                ;;
            4)  # キャンセル
                printf "%b" "${YELLOW}キャンセルしました${NC}\n"
                return 0
                ;;
        esac
    done

    # 確認された分解からタスクを作成
    local task_ids=()

    # Use mapfile to safely read JSON objects (avoids word splitting)
    mapfile -t subtasks < <(echo "$decomposition_json" | jq -c '.subtasks[]')

    for subtask_json in "${subtasks[@]}"; do
        local subtask_desc=$(echo "$subtask_json" | jq -r '.description')
        local subtask_agent=$(echo "$subtask_json" | jq -r '.agent')
        # 依存関係が空かnullの場合は空文字列に
        local subtask_deps=$(echo "$subtask_json" | jq -r 'if .dependencies == null or (.dependencies | length) == 0 then "" else (.dependencies | map(tostring) | join(",")) end')

        local deps_array_json="[]"
        if [[ -n "$subtask_deps" ]]; then
            # 依存タスクIDを変換（インデックスから実際のIDへ）
            local deps_list=()
            IFS=',' read -ra dep_indices <<< "$subtask_deps"
            for dep_idx in "${dep_indices[@]}"; do
                # インデックスが有効範囲内かチェック
                if [[ $dep_idx -ge 0 ]] && [[ $dep_idx -lt ${#task_ids[@]} ]]; then
                    deps_list+=("${task_ids[$dep_idx]}")
                fi
            done
            if [[ ${#deps_list[@]} -gt 0 ]]; then
                # JSON配列を生成（数値配列）
                deps_array_json=$(printf '%s\n' "${deps_list[@]}" | jq -R 'split("\n") | map(tonumber) | map(select(. != null))' | jq -s '.')
            fi
        fi

        add_task "$subtask_desc" "$subtask_agent" "$priority" "$deps_array_json"
        local task_id=$(jq -r '.last_id' "$TASKS_FILE")
        task_ids+=("$task_id")
    done

    # サマリー表示
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}✓ ${#task_ids[@]}個のタスクを作成しました${NC}\n"
    echo ""

    # エージェント自動起動（デフォルトで有効）
    if [[ ${#task_ids[@]} -gt 0 ]]; then
        # ORCH_NO_AUTO_LAUNCHが設定されている場合のみスキップ
        if [[ "${ORCH_NO_AUTO_LAUNCH:-}" == "yes" ]]; then
            printf "%b" "${YELLOW}エージェント自動起動は無効になっています${NC}\n"
            printf "%b" "${CYAN}手動で起動するには:${NC} orch start-agents\n"
            echo ""
        elif [[ "${ORCH_AUTO_LAUNCH:-yes}" == "yes" ]]; then
            printf "%b" "${GREEN}✓ エージェントを自動起動します...${NC}\n"
            echo ""
            launch_agents_background "${task_ids[@]}"
        fi
    fi
}

# サブタスク配列をJSONに変換（ルールベース用）
subtasks_array_to_json() {
    local subtasks=("$@")
    local json='{"subtasks": ['

    local i=0
    while [[ $i -lt ${#subtasks[@]} ]]; do
        if [[ $i -gt 0 ]]; then
            json+=','
        fi

        local desc="${subtasks[$i]}"
        local agent="${subtasks[$i+1]}"

        # JSONエスケープ (use printf to avoid trailing newline)
        desc=$(printf "%s" "$desc" | jq -Rs .)

        json+="{\"description\":$desc,\"agent\":\"$agent\",\"rationale\":\"ルールベース判定\",\"dependencies\":[]}"

        i=$((i + 2))
    done

    json+=']}'
    echo "$json"
}

# タスクに関連するエージェントを起動
launch_agents_for_tasks() {
    local task_ids=("$@")
    local unique_agents=()

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  エージェント自動起動${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # タスクから一意なエージェントを収集
    for task_id in "${task_ids[@]}"; do
        local agent=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .agent' "$TASKS_FILE")
        if [[ -n "$agent" && "$agent" != "null" && "$agent" != "orchestrator" ]]; then
            # 重チェック
            local found=0
            for a in "${unique_agents[@]}"; do
                if [[ "$a" == "$agent" ]]; then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                unique_agents+=("$agent")
            fi
        fi
    done

    if [[ ${#unique_agents[@]} -eq 0 ]]; then
        printf "%b" "${YELLOW}起動するエージェントがありません${NC}\n"
        return
    fi

    printf "%b" "${CYAN}以下のエージェントを起動します:${NC}\n"
    for agent in "${unique_agents[@]}"; do
        echo "  - ${MAGENTA}$agent${NC}"
    done
    echo ""

    # 各エージェントを新しいターミナルで起動
    for agent in "${unique_agents[@]}"; do
        printf "%b" "${GREEN}起動中: $agent${NC}\n"

        # macOS の場合
        if [[ "$OSTYPE" == "darwin"* ]]; then
            osascript <<EOF
tell application "Terminal"
    do script "cd '$PROJECT_ROOT' && '$AGENT_SCRIPT' $agent"
end tell
EOF
        # Linux の場合
        else
            if command -v gnome-terminal &> /dev/null; then
                gnome-terminal -- bash -c "cd '$PROJECT_ROOT' && '$AGENT_SCRIPT' $agent; exec bash"
            elif command -v xterm &> /dev/null; then
                xterm -e "cd '$PROJECT_ROOT' && '$AGENT_SCRIPT' $agent; bash" &
            else
                printf "%b" "${YELLOW}新しいターミナルが見つかりません。手動で起動してください:${NC}\n"
                echo "  $AGENT_SCRIPT $agent"
            fi
        fi
    done

    echo ""
    printf "%b" "${GREEN}✓ ${#unique_agents[@]}個のエージェントを起動しました${NC}\n"
    echo ""
    printf "%b" "${CYAN}各ターミナルで以下のコマンドを実行してタスクを開始してください:${NC}\n"
    for task_id in "${task_ids[@]}"; do
        local task_desc=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .description' "$TASKS_FILE")
        printf "%b" "  ${YELLOW}orchestrator.sh start $task_id${NC}  # $task_desc\n"
    done
    echo ""
}

# エージェントをバックグラウンドで起動（自動実行用）
launch_agents_background() {
    # 最後の引数がタイムアウト（数値のみ）かどうかをチェック
    local last_arg="${@: -1}"
    local timeout=""

    # タイムアウトが数値のみの場合は、タイムアウトとして扱う
    # ただし、引数が1つの場合はタスクIDとみなす（タイムアウトのみ指定して起動することはないため）
    if [[ "$last_arg" =~ ^[0-9]+$ ]] && [[ $# -gt 1 ]]; then
        timeout="$last_arg"
        # タイムアウトを除いたタスクIDを取得
        set -- "${@:1:$#-1}"
    fi

    local task_ids=("$@")
    local unique_agents=()

    # PID管理ディレクトリ
    local PID_DIR="$CLAUDE_DIR/pids"
    mkdir -p "$PID_DIR"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  エージェント自動起動（バックグラウンド）${NC}\n"
    if [[ -n "$timeout" ]]; then
        printf "%b" "${CYAN}  タイムアウト設定: ${timeout}秒${NC}\n"
    fi
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # タスクから一意なエージェントを収集
    for task_id in "${task_ids[@]}"; do
        local agent=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .agent' "$TASKS_FILE")
        if [[ -n "$agent" && "$agent" != "null" && "$agent" != "orchestrator" ]]; then
            # 重複チェック
            local found=0
            for a in "${unique_agents[@]}"; do
                if [[ "$a" == "$agent" ]]; then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                unique_agents+=("$agent")
            fi
        fi
    done

    if [[ ${#unique_agents[@]} -eq 0 ]]; then
        printf "%b" "${YELLOW}起動するエージェントがありません${NC}\n"
        return
    fi

    printf "%b" "${CYAN}以下のエージェントをバックグラウンドで起動します:${NC}\n"
    for agent in "${unique_agents[@]}"; do
        echo "  - ${MAGENTA}$agent${NC}"
    done
    echo ""

    # 各エージェントをバックグラウンドで起動
    for agent in "${unique_agents[@]}"; do
        local pid_file="$PID_DIR/${agent}.pid"
        local log_file="$LOGS_DIR/agent-$(date +%Y-%m-%d).log"

        # 既に実行中でないか確認
        if [[ -f "$pid_file" ]]; then
            local existing_pid=$(cat "$pid_file" 2>/dev/null)
            if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
                printf "%b" "${YELLOW}⚠ $agent は既に実行中です (PID: $existing_pid)${NC}\n"
                continue
            fi
        fi

        printf "%b" "${GREEN}起動中: $agent (watchモード)${NC} -> "

        # バックグラウンドでエージェントを起動（watchモード）
        # タイムアウトが指定されている場合は環境変数を設定
        if [[ -n "$timeout" ]]; then
            CLAUDE_TIMEOUT="$timeout" nohup bash "$AGENT_SCRIPT" "$agent" watch >> "$log_file" 2>&1 &
        else
            nohup bash "$AGENT_SCRIPT" "$agent" watch >> "$log_file" 2>&1 &
        fi
        local agent_pid=$!

        # PIDを記録
        echo "$agent_pid" > "$pid_file"

        # エージェント情報も記録（watchモードを記録）
        local agent_info_file="$PID_DIR/${agent}.json"
        jq -n \
            --arg agent "$agent" \
            --argjson pid "$agent_pid" \
            --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg mode "watch" \
            '{agent: $agent, pid: $pid, started_at: $started_at, mode: $mode}' > "$agent_info_file"

        printf "%b" "${GREEN}PID: $agent_pid${NC}\n"
    done

    echo ""
    printf "%b" "${GREEN}✓ ${#unique_agents[@]}個のエージェントをwatchモードで起動しました${NC}\n"
    echo ""
    printf "%b" "${CYAN}エージェントは常時待機し、タスクが来たら自動実行します${NC}\n"
    echo ""
    printf "%b" "${CYAN}監視コマンド:${NC} orch status, orch agents, orch log-tail\n"
    printf "%b" "${CYAN}停止コマンド:${NC} orch stop <agent>\n"
    echo ""
}

# すべての未着手タスクに対してエージェントを起動
launch_all_pending() {
    init_tasks

    local pending_tasks=($(jq -r '.tasks[] | select(.status == "pending") | .id' "$TASKS_FILE"))

    if [[ ${#pending_tasks[@]} -eq 0 ]]; then
        printf "%b" "${YELLOW}未着手のタスクはありません${NC}\n"
        return
    fi

    launch_agents_for_tasks "${pending_tasks[@]}"
}

# ==============================================================================
# エージェント制御コマンド
# ==============================================================================

# エージェントを停止
stop_agent() {
    local agent="$1"
    local PID_DIR="$CLAUDE_DIR/pids"
    local pid_file="$PID_DIR/${agent}.pid"

    if [[ ! -f "$pid_file" ]]; then
        printf "%b" "${YELLOW}エージェント '$agent' は実行されていません${NC}\n"
        return 1
    fi

    local pid=$(cat "$pid_file" 2>/dev/null)

    if [[ -z "$pid" ]]; then
        printf "%b" "${YELLOW}PIDファイルが空です${NC}\n"
        rm -f "$pid_file"
        return 1
    fi

    # プロセスが存在するか確認
    if ! kill -0 "$pid" 2>/dev/null; then
        printf "%b" "${YELLOW}エージェント '$agent' (PID: $pid) は既に終了しています${NC}\n"
        rm -f "$pid_file"
        return 1
    fi

    printf "%b" "${CYAN}エージェント '$agent' (PID: $pid) を停止中...${NC} "

    # グレースフルに停止 (SIGTERM)
    kill "$pid" 2>/dev/null

    # 最大5秒待機
    local count=0
    while kill -0 "$pid" 2>/dev/null && [[ $count -lt 5 ]]; do
        sleep 1
        count=$((count + 1))
    done

    # まだ生きている場合は強制終了 (SIGKILL)
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi

    # PIDファイルを削除
    rm -f "$pid_file"
    rm -f "$PID_DIR/${agent}.json"

    printf "%b" "${GREEN}✓ 停止しました${NC}\n"
}

# すべてのエージェントを停止
stop_all_agents() {
    local PID_DIR="$CLAUDE_DIR/pids"
    local found=false

    # まずPIDファイルからエージェントを停止
    if [[ -d "$PID_DIR" ]]; then
        for pid_file in "$PID_DIR"/*.pid; do
            if [[ -f "$pid_file" ]]; then
                local agent=$(basename "$pid_file" .pid)
                stop_agent "$agent"
                found=true
            fi
        done
    fi

    # フォールバック: 実行中のClaudeプロセスを直接探して停止
    # (PIDファイルがない場合や、外部から起動されたプロセス用)
    local claude_pids=$(pgrep -f "claude -p" | tr '\n' ' ')
    if [[ -n "$claude_pids" ]]; then
        printf "%b" "${YELLOW}追加で実行中のClaudeプロセスを停止中...${NC}\n"
        for pid in $claude_pids; do
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                # プロセスのコマンドラインを取得して確認
                local cmdline=$(ps -p "$pid" -o command= 2>/dev/null)
                if [[ "$cmdline" == *"claude -p"* ]]; then
                    printf "%b" "${CYAN}Claudeプロセス (PID: $pid) を停止中...${NC}\n"
                    kill "$pid" 2>/dev/null

                    # 最大5秒待機
                    local count=0
                    while kill -0 "$pid" 2>/dev/null && [[ $count -lt 5 ]]; do
                        sleep 1
                        count=$((count + 1))
                    done

                    # まだ生きている場合は強制終了
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -9 "$pid" 2>/dev/null
                        sleep 1
                    fi

                    printf "%b" "${GREEN}✓${NC} 停止完了\n"
                    found=true
                fi
            fi
        done
    fi

    if [[ "$found" == "false" ]]; then
        printf "%b" "${YELLOW}実行中のエージェントはありません${NC}\n"
    else
        # 残ったPIDファイルをクリーンアップ
        if [[ -d "$PID_DIR" ]]; then
            rm -f "$PID_DIR"/*.pid 2>/dev/null
            rm -f "$PID_DIR"/*.json 2>/dev/null
        fi

        # すべてのin_progressタスクをstoppedに変更
        local in_progress_count=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
        if [[ "$in_progress_count" -gt 0 ]]; then
            jq '(.tasks[] | select(.status == "in_progress")) |= (.status = "stopped")' "$TASKS_FILE" > "/tmp/tasks_stopped_$$.tmp"
            mv "/tmp/tasks_stopped_$$.tmp" "$TASKS_FILE"
            printf "%b" "${GREEN}✓ $in_progress_count 個のタスクを停止状態にしました${NC}\n"
        fi

        printf "%b" "${GREEN}すべてのエージェントを停止しました${NC}\n"
    fi
}

# エージェントを再起動
restart_agent() {
    local agent="$1"
    local timeout="${2:-}"  # オプション: タイムアウト秒数

    printf "%b" "${CYAN}エージェント '$agent' を再起動中...${NC}\n"
    if [[ -n "$timeout" ]]; then
        printf "%b" "${CYAN}  タイムアウト設定: ${timeout}秒${NC}\n"
    fi
    echo ""

    # まず停止を試みる（出力を抑制）
    stop_agent "$agent" >/dev/null 2>&1 || true

    # 少し待機
    sleep 1

    # 再起動
    printf "%b" "${CYAN}再起動中...${NC}\n"

    # stoppedタスクがある場合は、in_progressに戻す
    local stopped_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent and .status == "stopped")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    if [[ "$stopped_count" -gt 0 ]]; then
        jq --arg agent "$agent" '(.tasks[] | select(.agent == $agent and .status == "stopped")) |= (.status = "in_progress")' "$TASKS_FILE" > "/tmp/tasks_reset_stopped_$$.tmp"
        mv "/tmp/tasks_reset_stopped_$$.tmp" "$TASKS_FILE"
        printf "%b" "${GREEN}✓ $stopped_count 個のタスクを再開しました${NC}\n"
    fi

    # pendingタスクのIDを取得
    local pending_tasks=$(jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent and .status == "pending") | .id' "$TASKS_FILE" 2>/dev/null || echo "")

    # failedタスクがある場合は、常にpendingに戻す
    local failed_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent and .status == "failed")] | length' "$TASKS_FILE" 2>/dev/null || echo "0")
    if [[ "$failed_count" -gt 0 ]]; then
        jq --arg agent "$agent" '(.tasks[] | select(.agent == $agent and .status == "failed")) |= (.status = "pending" | .started_at = null)' "$TASKS_FILE" > "/tmp/tasks_reset_failed_$$.tmp"
        mv "/tmp/tasks_reset_failed_$$.tmp" "$TASKS_FILE"

        # failedタスクをpendingに戻したので、pendingタスクを再取得
        pending_tasks=$(jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent and .status == "pending") | .id' "$TASKS_FILE" 2>/dev/null || echo "")
    fi

    if [[ -n "$pending_tasks" ]]; then
        # pendingタスクがある場合は、そのタスクを指定して起動
        launch_agents_background $pending_tasks "$timeout"
    else
        # pendingタスクがない場合は、エージェントのすべてのタスクを一時的にpendingにして起動
        local agent_task_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent)] | length' "$TASKS_FILE" 2>/dev/null || echo "0")

        if [[ "$agent_task_count" -gt 0 ]]; then
            # エージェントのin_progressタスクを一時的にpendingにして起動
            jq --arg agent "$agent" '(.tasks[] | select(.agent == $agent and .status == "in_progress")) |= (.status = "pending" | .started_at = null)' "$TASKS_FILE" > "/tmp/tasks_restart_$$.tmp"
            mv "/tmp/tasks_restart_$$.tmp" "$TASKS_FILE"

            # pendingタスクを再取得
            pending_tasks=$(jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent and .status == "pending") | .id' "$TASKS_FILE" 2>/dev/null || echo "")
            launch_agents_background $pending_tasks "$timeout"
        else
            # エージェントにタスクがない場合は、直接起動
            launch_agent_direct "$agent" "$timeout"
        fi
    fi
}

# エージェントを直接起動（タスクなしの場合）
launch_agent_direct() {
    local agent="$1"
    local timeout="${2:-}"  # オプション: タイムアウト秒数
    local PID_DIR="$CLAUDE_DIR/pids"
    local pid_file="$PID_DIR/${agent}.pid"
    local log_file="$LOGS_DIR/agent-$(date +%Y-%m-%d).log"

    # 既に実行中でないか確認
    if [[ -f "$pid_file" ]]; then
        local existing_pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            printf "%b" "${YELLOW}⚠ $agent は既に実行中です (PID: $existing_pid)${NC}\n"
            return
        fi
    fi

    printf "%b" "${GREEN}起動中: $agent (watchモード)${NC} -> "

    # バックグラウンドでエージェントを起動（watchモード）
    # タイムアウトが指定されている場合は環境変数を設定
    if [[ -n "$timeout" ]]; then
        CLAUDE_TIMEOUT="$timeout" nohup bash "$AGENT_SCRIPT" "$agent" watch >> "$log_file" 2>&1 &
    else
        nohup bash "$AGENT_SCRIPT" "$agent" watch >> "$log_file" 2>&1 &
    fi
    local agent_pid=$!

    # PIDを記録
    echo "$agent_pid" > "$pid_file"

    # エージェント情報も記録（watchモードを記録）
    local agent_info_file="$PID_DIR/${agent}.json"
    jq -n \
        --arg agent "$agent" \
        --argjson pid "$agent_pid" \
        --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg mode "watch" \
        '{agent: $agent, pid: $pid, started_at: $started_at, mode: $mode}' > "$agent_info_file"

    printf "%b" "${GREEN}PID: $agent_pid${NC}\n"
    printf "%b" "${GREEN}✓ 1個のエージェントをwatchモードで起動しました${NC}\n"
    echo ""
    printf "%b" "${CYAN}エージェントは常時待機し、タスクが来たら自動実行します${NC}\n"
    echo ""
    printf "%b" "${CYAN}監視コマンド: orch status, orch agents, orch log-tail${NC}\n"
    printf "%b" "${CYAN}停止コマンド: orch stop <agent>${NC}\n"
}
# エージェントを削除（停止 + タスククリア）
remove_agent() {
    local agent="$1"

    printf "%b" "${CYAN}エージェント '$agent' を削除中...${NC}\n"

    # エージェントを停止
    stop_agent "$agent" 2>/dev/null || true

    # エージェントのタスクを削除
    init_tasks
    local task_count=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent)] | length' "$TASKS_FILE")

    if [[ "$task_count" -gt 0 ]]; then
        printf "%b" "${YELLOW}エージェント '$agent' の $task_count 個のタスクを削除しますか？ (y/N):${NC} "
        read -r -n 1 response
        echo ""

        if [[ "$response" =~ ^[Yy]$ ]]; then
            # タスクを削除
            jq --arg agent "$agent" 'del(.tasks[] | select(.agent == $agent))' "$TASKS_FILE" > "/tmp/tasks_$$.tmp"
            mv "/tmp/tasks_$$.tmp" "$TASKS_FILE"
            printf "%b" "${GREEN}✓ $task_count 個のタスクを削除しました${NC}\n"
        else
            printf "%b" "${YELLOW}キャンセルしました${NC}\n"
        fi
    else
        printf "%b" "${YELLOW}エージェント '$agent' のタスクはありません${NC}\n"
    fi
}

# オーケストレーターのリセット（エージェント状態、タスク、ログをクリア）
reset_orchestrator() {
    local keep_logs="${1:-false}"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  オーケストレーター・リセット${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # 確認
    if [[ "$keep_logs" == "true" ]]; then
        printf "%b" "${YELLOW}ログを保持したまま、以下をリセットします:${NC}\n"
    else
        printf "%b" "${YELLOW}以下をリセットします:${NC}\n"
    fi
    echo "  • すべてのエージェントプロセスの停止"
    echo "  • PIDファイルの削除"
    echo "  • タスクのクリア"
    if [[ "$keep_logs" == "false" ]]; then
        echo "  • ログファイルの削除"
    fi
    echo ""
    printf "%b" "${RED}この操作は取り消せません。続行しますか？ (y/N):${NC} "

    local confirm
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "%b" "${YELLOW}キャンセルしました${NC}\n"
        return 0
    fi

    echo ""
    printf "%b" "${CYAN}リセット中...${NC}\n"

    # 1. すべてのエージェントを停止
    echo "エージェントを停止中..."
    local PID_DIR="$CLAUDE_DIR/pids"
    if [[ -d "$PID_DIR" ]]; then
        for pid_file in "$PID_DIR"/*.pid; do
            if [[ -f "$pid_file" ]]; then
                local pid=$(cat "$pid_file" 2>/dev/null)
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null
                    printf "%b" "${GREEN}✓${NC} PID $pid を停止\n"
                fi
            fi
        done
    fi

    # 2. PIDファイルを削除
    echo "PIDファイルを削除中..."
    if [[ -d "$PID_DIR" ]]; then
        rm -f "$PID_DIR"/*.pid 2>/dev/null
        rm -f "$PID_DIR"/*.json 2>/dev/null
        printf "%b" "${GREEN}✓${NC} PIDファイルを削除\n"
    fi

    # 3. タスクをクリア
    echo "タスクをクリア中..."
    if [[ -f "$TASKS_FILE" ]]; then
        jq '{tasks: [], next_id: 1}' "$TASKS_FILE" > "/tmp/tasks_reset_$$.tmp"
        mv "/tmp/tasks_reset_$$.tmp" "$TASKS_FILE"
        printf "%b" "${GREEN}✓${NC} タスクをクリア\n"
    fi

    # 4. ログファイルの削除（オプション）
    if [[ "$keep_logs" == "false" ]]; then
        echo "ログファイルを削除中..."
        if [[ -d "$LOGS_DIR" ]]; then
            rm -f "$LOGS_DIR"/*.log 2>/dev/null
            rm -f "$LOGS_DIR"/*.log.gz 2>/dev/null
            printf "%b" "${GREEN}✓${NC} ログファイルを削除\n"
        fi
    else
        echo "ログファイルは保持されました"
    fi

    echo ""
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}✓ リセット完了${NC}\n"
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 実行中のエージェント一覧を表示
list_running_agents() {
    local PID_DIR="$CLAUDE_DIR/pids"

    if [[ ! -d "$PID_DIR" ]]; then
        printf "%b" "${YELLOW}実行中のエージェントはありません${NC}\n"
        return
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  実行中のエージェント${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    local found=false
    for pid_file in "$PID_DIR"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local agent=$(basename "$pid_file" .pid)
            local pid=$(cat "$pid_file" 2>/dev/null)
            local info_file="$PID_DIR/${agent}.json"

            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                found=true
                local started_at=""
                if [[ -f "$info_file" ]]; then
                    started_at=$(jq -r '.started_at' "$info_file" 2>/dev/null)
                fi

                # エージェント名に色を付ける
                local agent_color=""
                case "$agent" in
                    "frontend") agent_color="$BLUE" ;;
                    "backend") agent_color="$GREEN" ;;
                    "tests") agent_color="$YELLOW" ;;
                    "docs") agent_color="$MAGENTA" ;;
                    *) agent_color="$CYAN" ;;
                esac

                printf "%b" "${agent_color}${agent}${NC} "
                printf "%b" "${CYAN}(PID: ${pid})${NC} "

                if [[ -n "$started_at" ]]; then
                    local duration=$(($(date +%s) - $(date -jf "%Y-%m-%dT%H:%M:%SZ" +%s "$started_at" 2>/dev/null || echo "0")))
                    printf "%b" "${YELLOW}(${duration}秒経過)${NC}"
                fi

                echo ""
            else
                # プロセスが存在しない場合はPIDファイルを削除
                rm -f "$pid_file" "$info_file"
            fi
        fi
    done

    if [[ "$found" == "false" ]]; then
        printf "%b" "${YELLOW}実行中のエージェントはありません${NC}\n"
    fi

    echo ""
}

# ==============================================================================

# ==============================================================================
# 既存のタスク管理機能
# ==============================================================================

# JSONファイルからタスクを読み込んで実行
load_from_json() {
    local json_file="${1:-$CLAUDE_DIR/decomposition.json}"

    if [[ ! -f "$json_file" ]]; then
        printf "%b" "${RED}エラー: JSONファイルが見つかりません: $json_file${NC}\n" >&2
        printf "%b" "${YELLOW}ヒント: まず 'orch add' コマンドでタスク分解プランを作成してください${NC}\n" >&2
        return 1
    fi

    # JSONを読み込み
    local decomposition_json
    decomposition_json=$(cat "$json_file")

    # JSONの検証
    if ! echo "$decomposition_json" | jq empty 2>/dev/null; then
        printf "%b" "${RED}エラー: JSONファイルが無効です${NC}\n" >&2
        return 1
    fi

    # subtasksが存在するか確認
    local subtask_count=$(echo "$decomposition_json" | jq -r '.subtasks | length' 2>/dev/null)
    if [[ "$subtask_count" == "null" ]] || [[ "$subtask_count" -eq 0 ]]; then
        printf "%b" "${RED}エラー: JSONファイルにサブタスクが含まれていません${NC}\n" >&2
        return 1
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  JSONからタスクを読み込み${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}ファイル: ${json_file}${NC}\n"
    printf "%b" "${YELLOW}サブタスク数: $subtask_count${NC}\n"
    echo ""

    # 修正されるタスクを表示
    printf "%b" "${MAGENTA}以下のタスクを作成します:${NC}\n"
    echo "$decomposition_json" | jq -r '.subtasks[] | "  - " + .description + " (" + .agent + ")"' 2>/dev/null
    echo ""

    # タスクを作成
    local task_ids=()
    local subtasks=($(echo "$decomposition_json" | jq -c '.subtasks[]' 2>/dev/null))

    for subtask_json in "${subtasks[@]}"; do
        local subtask_desc=$(echo "$subtask_json" | jq -r '.description')
        local subtask_agent=$(echo "$subtask_json" | jq -r '.agent')
        local subtask_deps=$(echo "$subtask_json" | jq -r '
            if .dependencies == null or (.dependencies | length) == 0 then ""
            else (.dependencies | map(tostring) | join(","))
            end')

        local deps_array_json="[]"
        if [[ -n "$subtask_deps" ]]; then
            local deps_list=()
            IFS=',' read -ra dep_indices <<< "$subtask_deps"
            for dep_idx in "${dep_indices[@]}"; do
                if [[ $dep_idx -ge 0 ]] && [[ $dep_idx -lt ${#task_ids[@]} ]]; then
                    deps_list+=("${task_ids[$dep_idx]}")
                fi
            done
            if [[ ${#deps_list[@]} -gt 0 ]]; then
                # JSON配列を生成（数値配列）
                deps_array_json=$(printf '%s\n' "${deps_list[@]}" | jq -R 'split("\n") | map(tonumber) | map(select(. != null))' | jq -s '.')
            fi
        fi

        # タスクを追加
        local task_id=$(jq -r '.next_id' "$TASKS_FILE")
        add_task "$subtask_desc" "$subtask_agent" "normal" "$deps_array_json" > /dev/null 2>&1 || true
        task_ids+=("$task_id")

        # 進捗を表示
        local task_info=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE" 2>/dev/null)
        local task_status=$(echo "$task_info" | jq -r '.status')
        local task_agent=$(echo "$task_info" | jq -r '.agent')
        local agent_color=""
        case "$task_agent" in
            "frontend") agent_color="$BLUE";;
            "backend") agent_color="$GREEN";;
            "tests") agent_color="$YELLOW";;
            "docs") agent_color="$MAGENTA";;
            *) agent_color="$CYAN";;
        esac
        printf "%b" "${agent_color}✓${NC} [#$task_id] $subtask_desc\n"
    done

    echo ""
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}$subtask_count 個のタスクを作成しました${NC}\n"
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${CYAN}次のステップ:${NC}\n"
    printf "%b" "  ${GREEN}orch status${NC}         # タスク状況を確認\n"
    printf "%b" "  ${GREEN}orch launch${NC}         # エージェントを起動\n"
    printf "%b" "  ${GREEN}orch watch <agent>${NC}  # エージェントを自動監視モードで起動\n"
}

# タスク追加（手動エージェント指定）
# タスク追加（拡張版：契約・検証ステップ対応）
add_task() {
    local task_desc="$1"
    local agent="$2"
    local priority="${3:-normal}"
    local dependencies="${4:-[]}"
    local contract="${5:-null}"
    local deliverables="${6:-[]}"
    local verification_steps="${7:-[]}"
    local definition_of_done="${8:-[]}"

    init_tasks

    local task_id=$(generate_task_id)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 新規タスク作成（jqを使用して安全にJSONを構築）
    local new_task=$(jq -n \
        --argjson id "$task_id" \
        --arg desc "$task_desc" \
        --arg agent "$agent" \
        --arg priority "$priority" \
        --argjson deps "$dependencies" \
        --argjson contract "$contract" \
        --argjson deliv "$deliverables" \
        --argjson vsteps "$verification_steps" \
        --argjson dod "$definition_of_done" \
        --arg ts "$timestamp" \
        '{
          id: $id,
          description: $desc,
          agent: $agent,
          status: "pending",
          priority: $priority,
          dependencies: $deps,
          contract: $contract,
          deliverables: $deliv,
          verification_steps: $vsteps,
          definition_of_done: $dod,
          created_at: $ts,
          updated_at: $ts,
          started_at: null,
          completed_at: null,
          notes: [],
          review_comments: null,
          rejection_reason: null,
          related_adr: []
        }')

    # ログ記録
    orch_log "INFO" "タスク追加: [#$task_id] $task_desc (担当: $agent, 優先度: $priority)"

    # ロックを取得
    if ! acquire_lock; then
        printf "%b" "${RED}エラー: タスク追加失敗（ロック取得失敗）${NC}\n"
        return 1
    fi

    # タスクを追加（ロック保護）
    jq --argjson new_task "$new_task" \
       --argjson id "$task_id" \
       '.tasks += [$new_task] | .last_id = $id' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    # 循環依存チェック
    if ! detect_circular_dependency "$task_id"; then
        # 循環依存が見つかった場合、タスクを削除
        jq --argjson id "$task_id" \
           'del(.tasks[] | select(.id == $id))' \
           "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

        release_lock
        printf "%b" "${RED}エラー: 循環依存が検出されたため、タスクを追加できませんでした${NC}\n"
        return 1
    fi

    # ロックを解放
    release_lock

    printf "%b" "${GREEN}✓ タスクを追加しました [ID: $task_id]${NC}\n"
    printf "%b" "  ${CYAN}説明:${NC} $task_desc\n"
    printf "%b" "  ${CYAN}担当:${NC} $agent\n"
    printf "%b" "  ${CYAN}優先度:${NC} $priority\n"
    echo ""

    # 自動起動（デフォルトで有効）
    if [[ "${ORCH_NO_AUTO_LAUNCH:-}" != "yes" ]]; then
        printf "%b" "${GREEN}✓ エージェントを自動起動します...${NC}\n"
        echo ""
        launch_agents_background "$task_id"
    fi

    return 0
}

remove_task_by_id() {
    local task_id=$1

    # タスク情報を取得 (存在確認)
    local task=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [[ -z "$task" || "$task" == "null" ]]; then
        printf "%b" "${RED}エラー: タスク [ID: $task_id] が見つかりませんでした${NC}\n"
        return 1
    fi

    local task_desc=$(echo "$task" | jq -r '.description')

    # ロックを取得
    if ! acquire_lock; then
        printf "%b" "${RED}エラー: タスク削除失敗（ロック取得失敗）${NC}\n"
        return 1
    fi

    # タスクを削除
    jq --argjson id "$task_id" \
       'del(.tasks[] | select(.id == $id))' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    release_lock

    printf "%b" "${GREEN}✓ タスクを削除しました [ID: $task_id]${NC}\n"
    printf "%b" "  ${CYAN}説明:${NC} $task_desc\n"
}

start_task() {
    local task_id=$1
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # タスク情報を取得
    local task=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [[ -z "$task" || "$task" == "null" ]]; then
        printf "%b" "${RED}エラー: タスク [ID: $task_id] が見つかりませんでした${NC}\n"
        return 1
    fi

    local current_status=$(echo "$task" | jq -r '.status')
    if [[ "$current_status" != "pending" ]]; then
        printf "%b" "${YELLOW}タスク [ID: $task_id] は既に開始されているか、完了しています (状態: $current_status)${NC}\n"
        return 1
    fi

    local task_desc=$(echo "$task" | jq -r '.description')
    local task_agent=$(echo "$task" | jq -r '.agent')

    orch_log "INFO" "タスク開始: [#$task_id] $task_desc (担当: $task_agent)"

    jq --argjson id "$task_id" \
       --arg timestamp "$timestamp" \
       '.tasks |= map(if .id == $id then
           .status = "in_progress" |
           .started_at = $timestamp |
           .updated_at = $timestamp
       else . end)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    printf "%b" "${GREEN}✓ タスク [ID: $task_id] を開始しました${NC}\n"
}

complete_task() {
    local task_id=$1
    local notes="${2:-}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # タスク情報を取得
    local task=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
    if [[ -z "$task" || "$task" == "null" ]]; then
        printf "%b" "${RED}エラー: タスク [ID: $task_id] が見つかりませんでした${NC}\n"
        return 1
    fi

    local current_status=$(echo "$task" | jq -r '.status')
    if [[ "$current_status" != "in_progress" ]]; then
        printf "%b" "${YELLOW}タスク [ID: $task_id] は実行中ではありません (状態: $current_status)${NC}\n"
        return 1
    fi

    local task_desc=$(echo "$task" | jq -r '.description')
    local task_agent=$(echo "$task" | jq -r '.agent')

    orch_log "INFO" "タスク完了: [#$task_id] $task_desc (担当: $task_agent)"
    [[ -n "$notes" ]] && orch_log "INFO" "  メモ: $notes"

    if [[ -n "$notes" ]]; then
        jq --argjson id "$task_id" \
           --arg notes "$notes" \
           --arg timestamp "$timestamp" \
           '.tasks |= map(if .id == $id then
               .status = "completed" |
               .completed_at = $timestamp |
               .updated_at = $timestamp |
               .notes += [{"type": "complete", "text": $notes, "timestamp": $timestamp}]
           else . end)' \
           "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
    else
        jq --argjson id "$task_id" \
           --arg timestamp "$timestamp" \
           '.tasks |= map(if .id == $id then
               .status = "completed" |
               .completed_at = $timestamp |
               .updated_at = $timestamp
           else . end)' \
           "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
    fi

    printf "%b" "${GREEN}✓ タスク [ID: $task_id] を完了しました${NC}\n"
}

# タスク失敗
fail_task() {
    local task_id=$1
    local reason="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # タスク情報をログ
    local task_desc=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .description' "$TASKS_FILE")
    local task_agent=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .agent' "$TASKS_FILE")

    orch_log "ERROR" "タスク失敗: [#$task_id] $task_desc (担当: $task_agent)"
    orch_log "ERROR" "  理由: $reason"

    jq --argjson id "$task_id" \
       --arg reason "$reason" \
       --arg timestamp "$timestamp" \
       '.tasks |= map(if .id == $id then
           .status = "failed" |
           .updated_at = $timestamp |
           .notes += [{"type": "error", "text": $reason, "timestamp": $timestamp}]
       else . end)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    printf "%b" "${RED}✗ タスク [ID: $task_id] が失敗しました: $reason${NC}\n"
}

# タスクリセット（pendingに戻す）
reset_task() {
    local task_id=$1
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # タスク情報を取得
    local task_info=$(jq --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$task_info" ]]; then
        printf "%b" "${RED}エラー: タスクID $task_id が見つかりません${NC}\n"
        return 1
    fi

    local task_desc=$(jq -r '.description' <<< "$task_info")
    local task_status=$(jq -r '.status' <<< "$task_info")
    local task_agent=$(jq -r '.agent' <<< "$task_info")

    # 既にpendingの場合はメッセージのみ
    if [[ "$task_status" == "pending" ]]; then
        printf "%b" "${YELLOW}タスク [ID: $task_id] は既にpending状態です${NC}\n"
        return 0
    fi

    # ログ記録
    orch_log "INFO" "タスクリセット: [#$task_id] $task_desc (担当: $task_agent) 状態: $task_status -> pending"

    # タスクをpendingに戻す
    jq --argjson id "$task_id" \
       --arg timestamp "$timestamp" \
       '.tasks |= map(if .id == $id then
           .status = "pending" |
           .started_at = null |
           .updated_at = $timestamp |
           .notes += [{"type": "info", "text": "タスクをpendingにリセットしました", "timestamp": $timestamp}]
       else . end)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    printf "%b" "${GREEN}✓ タスク [ID: $task_id] をpendingにリセットしました: $task_desc${NC}\n"
}

# タスクリトライ（失敗したタスクを再実行可能にする）
retry_task() {
    local task_id=$1
    local max_retries="${2:-3}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # タスク情報を取得
    local task_info=$(jq --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$task_info" ]]; then
        printf "%b" "${RED}エラー: タスクID $task_id が見つかりません${NC}\n"
        return 1
    fi

    local task_desc=$(jq -r '.description' <<< "$task_info")
    local task_status=$(jq -r '.status' <<< "$task_info")
    local task_agent=$(jq -r '.agent' <<< "$task_info")
    local current_retries=$(jq -r '.retries // 0' <<< "$task_info")

    # 失敗またはタイムアウトしたタスクのみリトライ可能
    if [[ "$task_status" != "failed" ]]; then
        printf "%b" "${YELLOW}注意: タスク [ID: $task_id] はfailed状態ではありません（現在: $task_status）${NC}\n"
        printf "%b" "${CYAN}リセットするには: orch reset $task_id${NC}\n"
        return 1
    fi

    # 最大リトライ回数チェック
    if [[ $current_retries -ge $max_retries ]]; then
        printf "%b" "${RED}エラー: タスク [ID: $task_id] は最大リトライ回数($max_retries)に達しました${NC}\n"
        printf "%b" "${CYAN}強制的にリトライするには: orch reset $task_id && orch start $task_id${NC}\n"
        return 1
    fi

    local new_retries=$((current_retries + 1))

    # ログ記録
    orch_log "INFO" "タスクリトライ: [#$task_id] $task_desc (試行 $new_retries/$max_retries)"

    # タスクをpendingに戻してリトライ回数をインクリメント
    jq --argjson id "$task_id" \
       --argjson retries "$new_retries" \
       --arg timestamp "$timestamp" \
       '.tasks |= map(if .id == $id then
           .status = "pending" |
           .started_at = null |
           .completed_at = null |
           .result = null |
           .retries = $retries |
           .updated_at = $timestamp |
           .notes += [{"type": "retry", "text": "リトライ試行 \($retries)", "timestamp": $timestamp}]
       else . end)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    printf "%b" "${GREEN}✓ タスク [ID: $task_id] をリトライ可能にしました (試行 $new_retries/$max_retries)${NC}\n"
    printf "%b" "${CYAN}  実行するには: orch start $task_id${NC}\n"
}

# 全失敗タスクを一括リトライ
retry_all_failed() {
    local max_retries="${1:-3}"
    local failed_tasks=$(jq -r '[.tasks[] | select(.status == "failed") | .id] | @sh' "$TASKS_FILE" 2>/dev/null | tr -d "'")

    if [[ -z "$failed_tasks" ]]; then
        printf "%b" "${YELLOW}失敗したタスクはありません${NC}\n"
        return 0
    fi

    printf "%b" "${CYAN}失敗したタスクをリトライ可能にします...${NC}\n"
    echo ""

    local success_count=0
    local skip_count=0

    for task_id in $failed_tasks; do
        if retry_task "$task_id" "$max_retries" 2>/dev/null; then
            ((success_count++))
        else
            ((skip_count++))
        fi
    done

    echo ""
    printf "%b" "${GREEN}✓ $success_count 件のタスクをリトライ可能にしました${NC}\n"
    if [[ $skip_count -gt 0 ]]; then
        printf "%b" "${YELLOW}  $skip_count 件は最大リトライ回数に達しました${NC}\n"
    fi
}

# 並列エージェント実行
parallel_agents() {
    local agents=("$@")
    local valid_agents=("frontend" "backend" "tests" "docs" "architect" "reviewer")
    local launched_agents=()
    local log_dir="$CLAUDE_DIR/logs"
    mkdir -p "$log_dir"

    if [[ ${#agents[@]} -eq 0 ]]; then
        printf "%b" "${RED}エラー: エージェントを指定してください${NC}\n"
        echo "使用方法: $0 parallel <agent1> <agent2> ..."
        echo ""
        echo "例:"
        echo "  $0 parallel frontend backend    # FrontendとBackendを並列実行"
        echo "  $0 parallel all                  # 全エージェントを並列実行"
        echo ""
        echo "利用可能なエージェント: ${valid_agents[*]}"
        return 1
    fi

    # "all"が指定された場合は全エージェントを起動
    if [[ "$1" == "all" ]]; then
        agents=("${valid_agents[@]}")
    fi

    # エージェントの検証
    for agent in "${agents[@]}"; do
        if [[ ! " ${valid_agents[*]} " =~ " ${agent} " ]]; then
            printf "%b" "${YELLOW}警告: 不明なエージェント '$agent' をスキップします${NC}\n"
            continue
        fi
        launched_agents+=("$agent")
    done

    if [[ ${#launched_agents[@]} -eq 0 ]]; then
        printf "%b" "${RED}エラー: 有効なエージェントが指定されていません${NC}\n"
        return 1
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  並列エージェント起動${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # 各エージェントをバックグラウンドで起動
    for agent in "${launched_agents[@]}"; do
        local log_file="$log_dir/parallel-${agent}-$(date +%Y%m%d-%H%M%S).log"
        printf "%b" "${GREEN}🚀 起動中: ${agent}${NC} (ログ: $log_file)\n"

        # バックグラウンドでエージェントを起動
        nohup bash "$AGENT_SCRIPT" "$agent" watch > "$log_file" 2>&1 &
        local pid=$!

        # PIDファイルを作成
        echo "$pid" > "$CLAUDE_DIR/pids/${agent}.pid"
        echo "{\"started_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"pid\": $pid, \"mode\": \"parallel\"}" > "$CLAUDE_DIR/pids/${agent}.json"

        orch_log "INFO" "並列起動: $agent (PID: $pid)"
    done

    echo ""
    printf "%b" "${GREEN}✓ ${#launched_agents[@]} 個のエージェントを並列起動しました${NC}\n"
    echo ""
    printf "%b" "${CYAN}ステータス確認: $0 status${NC}\n"
    printf "%b" "${CYAN}全停止: $0 stop all${NC}\n"
    printf "%b" "${CYAN}エージェント一覧: $0 agents${NC}\n"
}

# タスク状況表示
show_status() {
    init_tasks

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク状況一覧${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    local total=$(jq '.tasks | length' "$TASKS_FILE")
    local pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")
    local in_progress=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$TASKS_FILE")
    local completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$TASKS_FILE")
    local failed=$(jq '[.tasks[] | select(.status == "failed")] | length' "$TASKS_FILE")
    local stopped=$(jq '[.tasks[] | select(.status == "stopped")] | length' "$TASKS_FILE")

    # サマリー表示
    printf "%b" "${CYAN}サマリー:${NC}\n"
    printf "%b" "  全体:     ${MAGENTA}$total${NC}\n"
    printf "%b" "  未着手:   ${YELLOW}$pending${NC}\n"
    printf "%b" "  実行中:   ${BLUE}$in_progress${NC}\n"
    printf "%b" "  完了:     ${GREEN}$completed${NC}\n"
    printf "%b" "  失敗:     ${RED}$failed${NC}\n"
    printf "%b" "  停止中:   ${MAGENTA}$stopped${NC}\n"
    echo ""

    # 進捗バー
    if [[ $total -gt 0 ]]; then
        local progress=$((completed * 100 / total))
        local bar_length=50
        local filled=$((progress * bar_length / 100))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=filled; i<bar_length; i++)); do bar+="░"; done
        printf "%b" "${CYAN}進捗:${NC} [$bar] $progress%\n"
        echo ""
    fi

    # タスク詳細
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}タスクリスト${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # 優先度順にソートして表示
    jq -r '.tasks | sort_by(.priority) | reverse | .[] |
        "\(.id)\t\(.status)\t\(.priority)\t\(.agent)\t\(.description)"' \
        "$TASKS_FILE" 2>/dev/null | while IFS=$'\t' read -r id status priority agent desc; do
        local status_icon=""
        local status_color=""
        case "$status" in
            "pending")
                status_icon="○"
                status_color="$YELLOW"
                ;;
            "in_progress")
                status_icon="●"
                status_color="$BLUE"
                ;;
            "completed")
                status_icon="✓"
                status_color="$GREEN"
                ;;
            "failed")
                status_icon="✗"
                status_color="$RED"
                ;;
            "stopped")
                status_icon="■"
                status_color="$MAGENTA"
                ;;
        esac

        local priority_mark=""
        case "$priority" in
            "critical") priority_mark="${RED}!!!${NC} " ;;
            "high") priority_mark="${YELLOW}!!${NC} " ;;
            "normal") priority_mark="" ;;
            "low") priority_mark="${CYAN}-${NC} " ;;
        esac

        printf "%b" "${status_color}${status_icon}${NC} [${CYAN}#${id}${NC}] ${priority_mark}${desc}\n"
        printf "%b" "    担当: ${MAGENTA}${agent}${NC} | 状態: ${status_color}${status}${NC}\n"
        echo ""
    done
}

# エージェント別タスク表示
show_agent_tasks() {
    local agent="$1"
    init_tasks

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  ${agent} エージェントのタスク${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent) |
        "\(.id)\t\(.status)\t\(.priority)\t\(.description)"' \
        "$TASKS_FILE" 2>/dev/null | while IFS=$'\t' read -r id status priority desc; do
        echo "  [#$id] $desc - $status"
    done
}

# エージェント別詳細ステータス表示
show_agents_status() {
    init_tasks

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  エージェント別ステータス${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    local agents=("frontend" "backend" "tests" "docs" "orchestrator")

    for agent in "${agents[@]}"; do
        # エージェントのタスクを取得（配列として）
        local agent_tasks_json=$(jq --arg agent "$agent" '[.tasks[] | select(.agent == $agent)]' "$TASKS_FILE" 2>/dev/null)
        local total=0 pending=0 in_progress=0 completed=0 failed=0

        if [[ -n "$agent_tasks_json" ]] && [[ "$agent_tasks_json" != "[]" ]]; then
            total=$(echo "$agent_tasks_json" | jq '. | length' 2>/dev/null || echo "0")
            pending=$(echo "$agent_tasks_json" | jq '[.[] | select(.status == "pending")] | length' 2>/dev/null || echo "0")
            in_progress=$(echo "$agent_tasks_json" | jq '[.[] | select(.status == "in_progress")] | length' 2>/dev/null || echo "0")
            completed=$(echo "$agent_tasks_json" | jq '[.[] | select(.status == "completed")] | length' 2>/dev/null || echo "0")
            failed=$(echo "$agent_tasks_json" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null || echo "0")
        fi

        # エージェント名と色
        local agent_color=""
        local agent_icon=""
        case "$agent" in
            "frontend")
                agent_color="$BLUE"
                agent_icon="🎨"
                ;;
            "backend")
                agent_color="$GREEN"
                agent_icon="⚙️"
                ;;
            "tests")
                agent_color="$YELLOW"
                agent_icon="🧪"
                ;;
            "docs")
                agent_color="$MAGENTA"
                agent_icon="📚"
                ;;
            "orchestrator")
                agent_color="$CYAN"
                agent_icon="🎯"
                ;;
        esac

        # ステータス表示
        local status_text=""
        if [[ $in_progress -gt 0 ]]; then
            status_text="${BLUE}作業中${NC}"
        elif [[ $pending -gt 0 ]]; then
            status_text="${YELLOW}待機中${NC}"
        elif [[ $completed -gt 0 ]] && [[ $total -eq $completed ]]; then
            status_text="${GREEN}完了${NC}"
        elif [[ $failed -gt 0 ]]; then
            status_text="${RED}エラーあり${NC}"
        else
            status_text="${CYAN}ー${NC}"
        fi

        # エージェントヘッダー（先頭文字を大文字に）
        case "$agent" in
            frontend) agent_capitalized="Frontend" ;;
            backend) agent_capitalized="Backend" ;;
            tests) agent_capitalized="Tests" ;;
            docs) agent_capitalized="Docs" ;;
            orchestrator) agent_capitalized="Orchestrator" ;;
            *) agent_capitalized="$agent" ;;
        esac
        printf "%b" "${agent_color}${agent_icon} ${agent_capitalized}${NC} [$status_text]\n"

        # タスク数表示
        if [[ $total -gt 0 ]]; then
            printf "%b" "  タスク: 全${total} | 未${YELLOW}${pending}${NC} | 執${BLUE}${in_progress}${NC} | 完${GREEN}${completed}${NC} | 失${RED}${failed}${NC}\n"

            # 現在作業中のタスクを表示
            if [[ $in_progress -gt 0 ]]; then
                echo ""
                printf "%b" "  ${BLUE}▶ 作業中のタスク:${NC}\n"
                echo "$agent_tasks_json" | jq -r '.[] | select(.status == "in_progress") | "  [#\(.id)] \(.description)"' | head -2
            fi

            # 次に待機しているタスク（依存関係が満たされたもののみ）
            if [[ $pending -gt 0 ]]; then
                # 依存関係チェックを行い、実行可能なタスクを取得
                local next_task=$(jq -r --arg agent "$agent" '
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
                    | "  [#\(.id)] \(.description)"
                ' "$TASKS_FILE" 2>/dev/null)

                if [[ -n "$next_task" ]]; then
                    echo ""
                    printf "%b" "  ${YELLOW}⏳ 次のタスク:${NC}\n"
                    echo "$next_task"
                else
                    # 依存関係待ちのタスクがある場合
                    local waiting_deps=$(echo "$agent_tasks_json" | jq -r '[.[] | select(.status == "pending" and (.dependencies | length) > 0)] | length' 2>/dev/null || echo "0")
                    if [[ $waiting_deps -gt 0 ]]; then
                        echo ""
                        printf "%b" "  ${YELLOW}⏳ 依存タスク完了待ち (${waiting_deps}件)${NC}\n"
                    fi
                fi
            fi
        else
            printf "%b" "  ${CYAN}タスクなし${NC}\n"
        fi

        echo ""
    done
}

# リアルタイムモニタリング
monitor_tasks() {
    local interval="${1:-5}"
    local show_agents="${2:-false}"

    printf "%b" "${CYAN}リアルタイムモニタリング開始 (Ctrl+C で終了)${NC}\n"
    printf "%b" "更新間隔: ${interval}秒\n"
    echo ""

    while true; do
        clear
        show_status
        echo ""
        if [[ "$show_agents" == "true" ]]; then
            show_agents_status
        fi
        printf "%b" "${CYAN}最終更新: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
        printf "%b" "${CYAN}コマンド:${NC} status, agents, next, help\n"
        sleep "$interval"
    done
}

# エージェント別モニタリング
monitor_agents() {
    local interval="${1:-5}"

    printf "%b" "${CYAN}エージェント別モニタリング開始 (Ctrl+C で終了)${NC}\n"
    printf "%b" "更新間隔: ${interval}秒\n"
    echo ""

    while true; do
        clear
        show_agents_status
        printf "%b" "${CYAN}最終更新: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
        sleep "$interval"
    done
}

# 依存関係チェック
check_dependencies() {
    local task_id=$1
    local deps=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .dependencies | join(" ")' "$TASKS_FILE")

    for dep_id in $deps; do
        local dep_status=$(jq -r --argjson id "$dep_id" '.tasks[] | select(.id == $id) | .status' "$TASKS_FILE")
        if [[ "$dep_status" != "completed" ]]; then
            printf "%b" "${YELLOW}⚠ 依存タスク [#$dep_id] が未完了です${NC}\n"
            return 1
        fi
    done
    return 0
}

# 次に実行可能なタスクを取得
get_next_tasks() {
    init_tasks

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  次に実行可能なタスク${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # pendingで依存関係が満たされているタスクを表示
    jq -r '.tasks[] | select(.status == "pending") |
        "\(.id)\t\(.description)\t\(.dependencies | join(","))"' \
        "$TASKS_FILE" 2>/dev/null | while IFS=$'\t' read -r id desc deps; do
        local ready="true"
        if [[ -n "$deps" ]]; then
            for dep_id in ${deps//,/ }; do
                local dep_status=$(jq -r --argjson did "$dep_id" '.tasks[] | select(.id == $did) | .status' "$TASKS_FILE")
                if [[ "$dep_status" != "completed" ]]; then
                    ready="false"
                    break
                fi
            done
        fi

        if [[ "$ready" == "true" ]]; then
            printf "%b" "  ${GREEN}[#$id]${NC} $desc\n"
        fi
    done
}

# =============================================================================
# タスク自動実行関数
# =============================================================================

# タスクを自動実行
execute_task() {
    local task_id="$1"
    local watch_mode="${2:-false}"
    local exec_script="$SCRIPT_DIR/execute_task.sh"

    if [[ ! -f "$exec_script" ]]; then
        printf "%b" "${RED}エラー: execute_task.sh が見つかりません: $exec_script${NC}\n"
        return 1
    fi

    orch_log "INFO" "タスク自動実行開始: #$task_id"

    if [[ "$watch_mode" == "true" ]]; then
        bash "$exec_script" "$task_id" --watch
    else
        bash "$exec_script" "$task_id"
    fi

    local result=$?
    if [[ $result -eq 0 ]]; then
        orch_log "INFO" "タスク自動実行成功: #$task_id"
        printf "%b" "${GREEN}✓ タスク #$task_id の実行が完了しました${NC}\n"
    else
        orch_log "ERROR" "タスク自動実行失敗: #$task_id"
        printf "%b" "${RED}✗ タスク #$task_id の実行に失敗しました${NC}\n"
    fi

    return $result
}

# すべての pending/in_progress タスクを自動実行
execute_all_pending() {
    local watch_mode="${1:-false}"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  すべての保留中タスクを自動実行${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    orch_log "INFO" "すべての保留中タスクの自動実行開始"

    # 実行可能なタスクリストを取得（依存関係チェック済み）
    local pending_tasks=$(jq -r '.tasks[] |
        select(.status == "pending" or .status == "in_progress") |
        "\(.id)\t\(.description)\t\(.agent)\t\(.status)"' "$TASKS_FILE")

    if [[ -z "$pending_tasks" ]]; then
        printf "%b" "${YELLOW}実行可能なタスクがありません${NC}\n"
        echo ""
        return 0
    fi

    local task_count=0
    local success_count=0
    local fail_count=0

    # タスクを1つずつ実行
    while IFS=$'\t' read -r task_id task_desc task_agent task_status; do
        task_count=$((task_count + 1))

        echo ""
        printf "%b" "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "%b" "${BLUE}  タスク #$task_count: #$task_id${NC}\n"
        printf "%b" "${BLUE}  $task_desc${NC}\n"
        printf "%b" "${BLUE}  担当: $task_agent | 状態: $task_status${NC}\n"
        printf "%b" "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        echo ""

        # 依存関係チェック
        local task_info=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
        local dependencies=$(echo "$task_info" | jq -r '.dependencies[]?' 2>/dev/null)

        local can_execute="true"
        if [[ -n "$dependencies" ]]; then
            for dep_id in $dependencies; do
                local dep_status=$(jq -r --argjson did "$dep_id" '.tasks[] | select(.id == $did) | .status' "$TASKS_FILE")
                if [[ "$dep_status" != "completed" ]]; then
                    printf "%b" "${YELLOW}⚠ 依存タスク #$dep_id が未完了のためスキップ${NC}\n"
                    can_execute="false"
                    break
                fi
            done
        fi

        if [[ "$can_execute" == "true" ]]; then
            if execute_task "$task_id" "$watch_mode"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        fi
    done <<< "$pending_tasks"

    echo ""
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  実行サマリー${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "  全タスク数: ${GREEN}%d${NC}\n" "$task_count"
    printf "  成功: ${GREEN}%d${NC}\n" "$success_count"
    printf "  失敗: ${RED}%d${NC}\n" "$fail_count"
    echo ""

    orch_log "INFO" "すべての保留中タスクの自動実行完了: total=$task_count, success=$success_count, failed=$fail_count"
}

# ==============================================================================
# レビュー関連関数
# ==============================================================================

# レビュー承認
approve_review() {
    local task_id="$1"
    local comments="${2:-}"

    # タスクを完了に移行
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$task_id" \
       --arg comments "$comments" \
       --arg timestamp "$timestamp" \
       '(.tasks[] | select(.id == $id)) |= (.status = "completed" | .completed_at = $timestamp | .review_comments = $comments)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    orch_log "INFO" "レビュー承認: [#$task_id]"
    printf "%b" "${GREEN}✓ タスク #$task_id を承認しました${NC}\n"
}

# レビュー却下
reject_review() {
    local task_id="$1"
    local reason="$2"

    # タスクをrejectedに移行
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$task_id" \
       --arg reason "$reason" \
       --arg timestamp "$timestamp" \
       '(.tasks[] | select(.id == $id)) |= (.status = "rejected" | .rejection_reason = $reason | .updated_at = $timestamp)' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    orch_log "WARN" "レビュー却下: [#$task_id] - $reason"
    printf "%b" "${YELLOW}⚠ タスク #$task_id を却下しました${NC}\n"
    printf "%b" "${CYAN}理由: ${NC}$reason\n"
}

# レビュータスク作成
create_review_task() {
    local original_task_id="$1"

    # 元のタスク情報を取得
    local original_task=$(jq --argjson id "$original_task_id" \
        '.tasks[] | select(.id == $id)' \
        "$TASKS_FILE")

    local original_desc=$(echo "$original_task" | jq -r '.description')
    local original_agent=$(echo "$original_task" | jq -r '.agent')

    # レビュータスクを作成
    add_task \
        "レビュー: $original_desc" \
        "reviewer" \
        "high" \
        "[$original_task_id]"

    local review_task_id=$(jq -r '.last_id' "$TASKS_FILE")
    echo "$review_task_id"
}

# ヘルプ表示
show_help() {
    cat << EOF
${CYAN}Orchestrator - タスク管理・モニタリングツール${NC}

${YELLOW}使用方法:${NC}
    $0 <command> [options]

${YELLOW}コマンド:${NC}
    ${GREEN}status${NC}                       全タスクの状況表示
    ${GREEN}agents${NC}                       エージェント別ステータス表示
    ${GREEN}add <task> [agent] [prio]${NC}    タスク追加
                                       エージェント省略で自動振り分け・分解
    ${GREEN}start <task_id>${NC}              タスク開始
    ${GREEN}complete <task_id> [note]${NC}    タスク完了（ノート付き）
    ${GREEN}fail <task_id> <reason>${NC}      タスク失敗
    ${GREEN}reset <task_id>${NC}              タスクをpendingにリセット
    ${GREEN}agent <agent_name>${NC}           エージェント別タスク詳細表示
    ${GREEN}next${NC}                         次に実行可能なタスク表示
    ${GREEN}launch${NC}                       未着手タスクのエージェントを起動
    ${GREEN}monitor [interval]${NC}           全タスクのリアルタイムモニタリング
                                       デフォルト更新間隔: 5秒
    ${GREEN}monitor-agents [interval]${NC}    エージェント別リアルタイムモニタリング
                                       各エージェントの作業状態を監視

${YELLOW}依存関係自動管理:${NC}
    ${GREEN}wait <task_id> [interval]${NC}    依存タスクの完了を待機
                                       デフォルトチェック間隔: 5秒
    ${GREEN}auto <agent>${NC}                 エージェントの次タスクを自動開始
                                       依存タスクがあれば自動待機
    ${GREEN}watch <agent> [interval]${NC}     エージェント自動監視モード
                                       新しいタスクを自動検出・実行
                                       デフォルトチェック間隔: 10秒

${YELLOW}タスク自動実行:${NC}
    ${GREEN}exec <task_id> [--watch]${NC}     タスクを自動実行
                                       Claude Code APIを使用して実行
                                       --watch: 実行結果を表示
    ${GREEN}exec-all [--watch]${NC}           すべての保留中タスクを自動実行
                                       依存関係をチェックして順次実行

${YELLOW}ログ:${NC}
    ${GREEN}logs [-n N] [-e] [-t ID]${NC}   エージェントのログを表示
                                       -n N: 最近N行を表示（デフォルト: 50）
                                       -e: エラーのみ表示
                                       -t ID: タスクIDでフィルタ
    ${GREEN}log-tail${NC}                    ログをリアルタイム監視
    ${GREEN}logs-errors${NC}                 エラーログのみを一覧表示

${YELLOW}TUI (Terminal UI):${NC}
    ${GREEN}interactive${NC}                  インタラクティブTUIを起動
                                       vim風キーバインドでタスク管理
    ${GREEN}dashboard [--watch|--loop]${NC}  メインダッシュボードを表示
                                       --watch: 5秒ごと自動更新
                                       --loop: Enterで更新
    ${GREEN}board${NC}                       タスクボード（カンバン）を表示（インタラクティブ）
    ${GREEN}logs-tui [-f] [-n N] [-e]${NC}  TUIライブログビューア
                                       -f: フォローモード
                                       -n N: 表示行数指定
                                       -e: エラーのみ

${YELLOW}Worktree 操作:${NC}
    ${GREEN}worktree${NC}                    Git Worktree 操作サブコマンド
    ${GREEN}worktree create <agent>${NC}      エージェント用 Worktree 作成
    ${GREEN}worktree remove <agent>${NC}      Worktree 削除
    ${GREEN}worktree list${NC}               Worktree 一覧表示
    ${GREEN}worktree cleanup${NC}            Worktree クリーンアップ
    ${GREEN}worktree launch <agent>${NC}      Worktree でエージェント起動

${YELLOW}Worktree モード:${NC}
    ${GREEN}USE_WORKTREE=true orch watch <agent>${NC}
                                       Worktree を使用して自動監視

${YELLOW}レビュー:${NC}
    ${GREEN}review <task_id>${NC}             タスクをレビュー待ちに移行
    ${GREEN}approve <task_id> [comment]${NC}  レビュー承認（タスク完了）
    ${GREEN}reject <task_id> <reason>${NC}     レビュー却下
    ${GREEN}review-create <task_id>${NC}       レビュータスクを作成

${YELLOW}管理:${NC}
    ${GREEN}reset [--keep-logs]${NC}         オーケストレーターをリセット
                                       すべてのエージェントを停止し、タスクをクリア
                                       --keep-logs: ログファイルを保持
    ${GREEN}stop <agent|all>${NC}            エージェントを停止
    ${GREEN}restart <agent>${NC}             エージェントを再起動
    ${GREEN}list${NC}                        実行中のエージェントを一覧表示

${YELLOW}自動振り分け例:${NC}
    $0 add "ユーザー認証機能の実装"
    -> 自動的に複数タスクに分解され、各エージェントに振り分けられます

${YELLOW}手動指定例:${NC}
    $0 add "ログインUI実装" frontend high

${YELLOW}エージェント自動判定キーワード:${NC}
  ${MAGENTA}Frontend${NC}: UI, 画面, コンポーネント, スタイル, フォーム, ボタン...
  ${MAGENTA}Backend${NC}: API, サーバー, データベース, 認証, ログイン, モデル...
  ${MAGENTA}Tests${NC}: テスト, スペック, カバレッジ, モック...
  ${MAGENTA}Docs${NC}: ドキュメント, README, 仕様書...

${YELLOW}依存関係管理例:${NC}
    # タスク2はタスク1に依存
    $0 add "データベース設計" backend high          # Task #1
    $0 add "ユーザーAPI実装" backend normal [1]      # Task #2 (Task #1 に依存)

    # 依存タスクの完了を待機して開始
    $0 wait 2    # Task #1 が完了するまで待機
    $0 auto backend    # Backend の次タスクを自動開始

    # 自動監視モード（推奨）
    $0 watch backend    # 新しいタスクを自動検出・実行

EOF
}

# ==============================================================================
# Git Worktree 管理
# ==============================================================================

# Worktree 一覧表示
worktree_list() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  Git Worktree 一覧${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    if [[ ! -d "$WORKTREES_DIR" ]]; then
        printf "%b" "${YELLOW}Worktree ディレクトリがありません${NC}\n"
        printf "%b" "${CYAN}作成するには: ${GREEN}orch worktree create <agent>${NC}\n"
        return
    fi

    local count=0
    for worktree in "$WORKTREES_DIR"/*; do
        if [[ -d "$worktree" ]]; then
            local name=$(basename "$worktree")
            count=$((count + 1))

            # ブランチ名を取得
            local branch=""
            if cd "$worktree" 2>/dev/null; then
                branch=$(git branch --show-current 2>/dev/null || echo "detached")
            fi

            # ステータス
            local status="○"
            local status_color="$YELLOW"
            if [[ -d "$worktree/.git" ]]; then
                status="✓"
                status_color="$GREEN"
            fi

            printf "%b" "${status_color}${status}${NC} ${CYAN}${name}${NC} (${MAGENTA}${branch}${NC})\n"
        fi
    done

    if [[ $count -eq 0 ]]; then
        printf "%b" "${YELLOW}Worktree が作成されていません${NC}\n"
    else
        echo ""
        printf "%b" "${GREEN}計 ${count}個の Worktree${NC}\n"
    fi
    echo ""
}

# Worktree 作成
worktree_create() {
    local agent="$1"

    if [[ -z "$agent" ]]; then
        printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
        echo "使用方法: $0 worktree create <agent>"
        exit 1
    fi

    # Git リポジトリチェック
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        printf "%b" "${RED}エラー: Git リポジトリではありません${NC}\n"
        exit 1
    fi

    # Worktree ディレクトリ作成
    mkdir -p "$WORKTREES_DIR"

    local worktree_path="$WORKTREES_DIR/$agent"

    if [[ -d "$worktree_path" ]]; then
        printf "%b" "${YELLOW}⚠ Worktree '${agent}' は既に存在します${NC}\n"
        return
    fi

    # 現在のブランチを取得
    local current_branch=$(git branch --show-current)

    printf "%b" "${CYAN}Worktree を作成中: ${MAGENTA}${agent}${NC}${NC}\n"
    printf "%b" "  ベースブランチ: ${MAGENTA}${current_branch}${NC}\n"
    echo ""

    # Worktree 作成
    git worktree add "$worktree_path" -b "agent/$agent" "$current_branch"

    if [[ $? -eq 0 ]]; then
        printf "%b" "${GREEN}✓ Worktree を作成しました: ${worktree_path}${NC}\n"
        echo ""
        printf "%b" "${CYAN}エージェントを起動するには:${NC}\n"
        printf "%b" "  ${GREEN}cd ${worktree_path} && ../../agent.sh ${agent}${NC}\n"
        echo ""
        printf "%b" "${CYAN}または、Worktreeモードで起動:${NC}\n"
        printf "%b" "  ${GREEN}USE_WORKTREE=true orch agent ${agent}${NC}\n"
        echo ""
    else
        printf "%b" "${RED}✗ Worktree の作成に失敗しました${NC}\n"
        exit 1
    fi
}

# Worktree 削除
worktree_remove() {
    local agent="$1"

    if [[ -z "$agent" ]]; then
        printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
        echo "使用方法: $0 worktree remove <agent>"
        exit 1
    fi

    local worktree_path="$WORKTREES_DIR/$agent"

    if [[ ! -d "$worktree_path" ]]; then
        printf "%b" "${RED}エラー: Worktree '${agent}' が見つかりません${NC}\n"
        exit 1
    fi

    printf "%b" "${YELLOW}Worktree を削除: ${MAGENTA}${agent}${NC}${NC}\n"
    echo ""

    # Worktree 削除
    cd "$PROJECT_ROOT" && git worktree remove "$worktree_path"

    if [[ $? -eq 0 ]]; then
        printf "%b" "${GREEN}✓ Worktree を削除しました${NC}\n"
        echo ""
    else
        printf "%b" "${RED}✗ Worktree の削除に失敗しました${NC}\n"
        exit 1
    fi
}

# Worktree クリーンアップ
worktree_cleanup() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  Worktree クリーンアップ${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        printf "%b" "${RED}エラー: Git リポジトリではありません${NC}\n"
        exit 1
    fi

    # プルーニング実行
    git worktree prune

    printf "%b" "${GREEN}✓ Worktree をプルーニングしました${NC}\n"
    echo ""

    worktree_list
}

# Worktree でエージェントを起動
worktree_launch_agent() {
    local agent="$1"

    if [[ -z "$agent" ]]; then
        printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
        echo "使用方法: $0 worktree launch <agent>"
        exit 1
    fi

    local worktree_path="$WORKTREES_DIR/$agent"

    if [[ ! -d "$worktree_path" ]]; then
        printf "%b" "${RED}エラー: Worktree '${agent}' が見つかりません${NC}\n"
        printf "%b" "${CYAN}作成するには: ${GREEN}orch worktree create $agent${NC}\n"
        exit 1
    fi

    printf "%b" "${CYAN}Worktree モードでエージェントを起動: ${MAGENTA}${agent}${NC}${NC}\n"
    printf "%b" "  Worktree: ${worktree_path}\n"
    echo ""

    # 新しいターミナルで起動
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript <<EOF
tell application "Terminal"
    do script "cd '$worktree_path' && '../../agent.sh' $agent"
end tell
EOF
    else
        printf "%b" "${CYAN}手動で起動:${NC}\n"
        echo "  cd ${worktree_path} && ../../agent.sh ${agent}"
    fi
}

# =============================================================================
# 依存関係可視化
# =============================================================================

# 依存関係を表示
show_dependencies() {
    local task_id="$1"

    if [[ -z "$task_id" ]]; then
        printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
        echo "使用方法: $0 deps <task_id>"
        exit 1
    fi

    # タスクの存在確認
    local task_exists=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .id' \
        "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$task_exists" ]]; then
        printf "%b" "${RED}エラー: タスク #$task_id が見つかりません${NC}\n"
        exit 1
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク #$task_id の依存関係${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # タスク情報
    local task_desc=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .description' \
        "$TASKS_FILE")
    local task_status=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .status' \
        "$TASKS_FILE")

    printf "%b" "${YELLOW}タスク:${NC} #$task_id - $task_desc\n"
    printf "%b" "${YELLOW}ステータス:${NC} $task_status\n"
    echo ""

    # 依存先（このタスクが依存しているタスク）
    printf "%b" "${BLUE}依存先（ブロッカー）:${NC}\n"
    local dependencies=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.id == $id) | .dependencies[]? // empty' \
        "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$dependencies" ]]; then
        printf "%b" "${GREEN}  なし（タスクを開始できます）${NC}\n"
    else
        while IFS= read -r dep_id; do
            [[ -z "$dep_id" ]] && continue
            local dep_desc=$(jq -r --argjson id "$dep_id" \
                '.tasks[] | select(.id == $id) | .description' \
                "$TASKS_FILE")
            local dep_status=$(jq -r --argjson id "$dep_id" \
                '.tasks[] | select(.id == $id) | .status' \
                "$TASKS_FILE")

            # ステータスに応じて色分け
            local status_color=""
            case "$dep_status" in
                "completed") status_color="$GREEN" ;;
                "in_progress") status_color="$YELLOW" ;;
                "pending") status_color="$YELLOW" ;;
                "review_needed") status_color="$CYAN" ;;
                "rejected") status_color="$RED" ;;
                *) status_color="$NC" ;;
            esac

            printf "  ${CYAN}#$dep_id${NC}: $dep_desc [${status_color}${dep_status}${NC}]"
        done <<< "$dependencies"
    fi
    echo ""

    # 依存元（このタスクを待っているタスク）
    printf "%b" "${BLUE}依存元（このタスクを待っているタスク）:${NC}\n"
    local dependents=$(jq -r --argjson id "$task_id" \
        '.tasks[] | select(.dependencies != null and (.dependencies | contains([$id]))) |
         "\(.id)\t\(.description)\t\(.status)"' \
        "$TASKS_FILE" 2>/dev/null)

    if [[ -z "$dependents" ]]; then
        printf "%b" "${GREEN}  なし${NC}\n"
    else
        while IFS=$'\t' read -r dep_id dep_desc dep_status; do
            [[ -z "$dep_id" ]] && continue

            # ステータスに応じて色分け
            local status_color=""
            case "$dep_status" in
                "completed") status_color="$GREEN" ;;
                "in_progress") status_color="$YELLOW" ;;
                "pending") status_color="$YELLOW" ;;
                "review_needed") status_color="$CYAN" ;;
                "rejected") status_color="$RED" ;;
                *) status_color="$NC" ;;
            esac

            printf "  ${CYAN}#$dep_id${NC}: $dep_desc [${status_color}${dep_status}${NC}]\n"
        done <<< "$dependents"
    fi
    echo ""
}

# 循環依存検出
detect_circular_dependency() {
    local task_id="$1"
    local visited=()

    # 再帰的に依存関係をチェック
    check_circular() {
        local current_id="$1"
        local depth="${2:-0}"

        # 深さ制限（無限ループ防止）
        if [[ $depth -gt 50 ]]; then
            printf "%b" "${RED}エラー: 依存関係が深すぎます（循環の可能性）${NC}\n" >&2
            return 1
        fi

        # 訪問済みチェック
        for visited_id in "${visited[@]}"; do
            if [[ "$visited_id" == "$current_id" ]]; then
                printf "%b" "${RED}エラー: 循環依存を検出: #$current_id${NC}\n" >&2
                return 1
            fi
        done

        visited+=("$current_id")

        # 依存先を取得
        local deps=$(jq -r --argjson id "$current_id" \
            '.tasks[] | select(.id == $id) | .dependencies[]? // empty' \
            "$TASKS_FILE" 2>/dev/null)

        # 依存先を再帰的にチェック
        while IFS= read -r dep_id; do
            [[ -z "$dep_id" ]] && continue
            if ! check_circular "$dep_id" $((depth + 1)); then
                return 1
            fi
        done <<< "$deps"

        return 0
    }

    check_circular "$task_id"
}

# =============================================================================
# Worktreeでのエージェント起動（タスク単位）
# =============================================================================

# Worktreeでエージェントを起動（タスク単位）
start_agent_with_worktree() {
    local agent="$1"
    local task_id="$2"

    # Worktree名を生成
    local worktree_name="${agent}-task-${task_id}"
    local worktree_path="$WORKTREES_DIR/$worktree_name"

    # Worktreeディレクトリ作成
    mkdir -p "$WORKTREES_DIR"

    # Worktreeが既に存在する場合は確認
    if [[ -d "$worktree_path" ]]; then
        printf "%b" "${YELLOW}Worktreeが既に存在します: $worktree_name${NC}\n"
        printf "%b" "${CYAN}既存のWorktreeを使用します...${NC}\n"
    else
        # Git リポジトリチェック
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            printf "%b" "${RED}エラー: Git リポジトリではありません${NC}\n"
            return 1
        fi

        # 現在のブランチを取得
        local current_branch=$(git branch --show-current)

        printf "%b" "${CYAN}Worktreeを作成中: ${MAGENTA}${worktree_name}${NC}\n"
        printf "%b" "  ベースブランチ: ${MAGENTA}${current_branch}${NC}\n"

        # Worktreeを作成
        if ! git worktree add "$worktree_path" -b "$worktree_name" "$current_branch"; then
            printf "%b" "${RED}エラー: Worktreeの作成に失敗しました${NC}\n"
            return 1
        fi

        printf "%b" "${GREEN}✓ Worktreeを作成しました: $worktree_path${NC}\n"
    fi

    echo ""
    printf "%b" "${CYAN}エージェントをWorktreeで起動: ${MAGENTA}${agent}${NC}\n"
    printf "%b" "  Worktree: $worktree_path${NC}\n"
    echo ""

    # Worktree内でエージェントを実行
    (
        cd "$worktree_path"
        # 相対パスでagent.shを呼び出し
        bash "$CLAUDE_DIR/agent.sh" "$agent"
    )

    return $?
}

# =============================================================================
# 依存関係自動管理機能
# ==============================================================================

# 依存タスクが完了するまで待機
wait_for_dependencies() {
    local task_id=$1
    local check_interval=${2:-5}  # デフォルト5秒ごとにチェック

    init_tasks

    local deps=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .dependencies | join(" ")' "$TASKS_FILE")

    if [[ -z "$deps" || "$deps" == "null" ]]; then
        return 0  # 依存タスクなし
    fi

    printf "%b" "${CYAN}依存タスクの完了を待機開始...${NC}\n"
    echo ""

    while true; do
        local all_complete=true
        local pending_deps=()

        for dep_id in $deps; do
            local dep_status=$(jq -r --argjson did "$dep_id" '.tasks[] | select(.id == $did) | .status' "$TASKS_FILE")
            local dep_desc=$(jq -r --argjson did "$dep_id" '.tasks[] | select(.id == $did) | .description' "$TASKS_FILE")

            case "$dep_status" in
                "completed")
                    # 完了済み - スキップ
                    ;;
                "failed")
                    printf "%b" "${RED}✗ 依存タスク [#$dep_id] が失敗しました${NC}\n"
                    printf "%b" "  ${YELLOW}$dep_desc${NC}\n"
                    return 1
                    ;;
                *)
                    all_complete=false
                    pending_deps+=("[#$dep_id] $dep_desc ($dep_status)")
                    ;;
            esac
        done

        if [[ "$all_complete" == "true" ]]; then
            printf "%b" "${GREEN}✓ すべての依存タスクが完了しました${NC}\n"
            echo ""
            return 0
        fi

        # 待機中の依存タスクを表示
        clear
        printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "%b" "${CYAN}  依存タスク待機中 [#$task_id]${NC}\n"
        printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        echo ""
        printf "%b" "${YELLOW}待機中の依存タスク:${NC}\n"
        for dep in "${pending_deps[@]}"; do
            printf "%b" "  ${YELLOW}⏳ $dep${NC}\n"
        done
        echo ""
        printf "%b" "${CYAN}最終更新: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
        printf "%b" "${CYAN}次のチェック: ${check_interval}秒後... (Ctrl+C でキャンセル)${NC}\n"

        sleep "$check_interval"
    done
}

# エージェントの次のタスクを自動開始
auto_start_next() {
    local agent="$1"
    local wait_for_deps="${2:-true}"

    init_tasks

    # 次の待機中タスクを取得
    local next_task=$(jq -r --arg agent "$agent" \
        '.tasks[] | select(.agent == $agent and .status == "pending") | "\(.id)\t\(.description)"' \
        "$TASKS_FILE" | head -1)

    if [[ -z "$next_task" ]]; then
        printf "%b" "${YELLOW}$(capitalize_agent "$agent") エージェントに待機中のタスクはありません${NC}\n"
        return
    fi

    local task_id=$(echo "$next_task" | cut -f1)
    local task_desc=$(echo "$next_task" | cut -f2)

    printf "%b" "${CYAN}$(capitalize_agent "$agent") エージェントの次のタスク:${NC}\n"
    printf "%b" "  ${GREEN}[#$task_id]${NC} $task_desc\n"
    echo ""

    # 依存関係チェック
    if [[ "$wait_for_deps" == "true" ]]; then
        if ! wait_for_dependencies "$task_id"; then
            printf "%b" "${RED}依存タスクの待機が中断されました${NC}\n"
            return 1
        fi
    fi

    # タスク開始
    start_task "$task_id"

    echo ""
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}✓ タスクを開始しました${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${CYAN}以下のコマンドでエージェントを起動してください:${NC}\n"
    printf "%b" "  ${GREEN}./.claude/agent.sh $agent${NC}\n"
    echo ""
    printf "%b" "${CYAN}または Worktree モード:${NC}\n"
    printf "%b" "  ${GREEN}orch worktree launch $agent${NC}\n"
    echo ""
}

# エージェント自動監視モード（次のタスクを監視して自動開始）
watch_agent() {
    local agent="$1"
    local check_interval="${2:-10}"

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  $(capitalize_agent "$agent") エージェント自動監視モード${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${CYAN}更新間隔: ${check_interval}秒 | Ctrl+C で終了${NC}\n"
    echo ""

    while true; do
        init_tasks

        # 待機中のタスクをチェック
        local pending_count=$(jq -r --arg agent "$agent" \
            '[.tasks[] | select(.agent == $agent and .status == "pending")] | length' \
            "$TASKS_FILE")

        if [[ $pending_count -gt 0 ]]; then
            # 次のタスクを取得
            local next_task=$(jq -r --arg agent "$agent" \
                '.tasks[] | select(.agent == $agent and .status == "pending") | "\(.id)\t\(.description)"' \
                "$TASKS_FILE" | head -1)

            local task_id=$(echo "$next_task" | cut -f1)
            local task_desc=$(echo "$next_task" | cut -f2)

            clear
            printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            printf "%b" "${CYAN}  $(capitalize_agent "$agent") エージェント自動監視モード${NC}\n"
            printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            echo ""
            printf "%b" "${GREEN}▶ 次のタスクが見つかりました:${NC}\n"
            printf "%b" "  ${YELLOW}[#$task_id]${NC} $task_desc\n"
            echo ""

            # 依存関係をチェック
            local deps=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .dependencies | join(" ")' "$TASKS_FILE")

            if [[ -n "$deps" && "$deps" != "null" ]]; then
                printf "%b" "${YELLOW}依存タスクがあります。完了を待機します...${NC}\n"
                echo ""

                if wait_for_dependencies "$task_id" "$check_interval"; then
                    # 依存タスク完了 - タスク開始
                    start_task "$task_id"

                    echo ""
                    printf "%b" "${GREEN}✓ 自動でタスクを開始しました${NC}\n"
                    echo ""

                    # エージェントを起動
                    printf "%b" "${CYAN}エージェントを起動します...${NC}\n"
                    if [[ "$USE_WORKTREE" == "true" ]]; then
                        worktree_launch_agent "$agent"
                    else
                        if [[ "$OSTYPE" == "darwin"* ]]; then
                            osascript <<EOF
tell application "Terminal"
    do script "cd '$PROJECT_ROOT' && '$AGENT_SCRIPT' $agent"
end tell
EOF
                        else
                            "$AGENT_SCRIPT" "$agent"
                        fi
                    fi

                    # このタスクが完了するまで監視
                    while true; do
                        sleep "$check_interval"
                        local status=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TASKS_FILE")
                        if [[ "$status" == "completed" || "$status" == "failed" ]]; then
                            printf "%b" "${CYAN}タスク [#$task_id] が${status}しました${NC}\n"
                            echo ""
                            break
                        fi
                    done
                else
                    printf "%b" "${RED}依存タスクの待機が失敗しました${NC}\n"
                    sleep 5
                fi
            else
                # 依存タスクなし - すぐに開始
                start_task "$task_id"
                echo ""
                printf "%b" "${GREEN}✓ 自動でタスクを開始しました${NC}\n"
                echo ""

                # エージェントを起動
                printf "%b" "${CYAN}エージェントを起動します...${NC}\n"
                if [[ "$USE_WORKTREE" == "true" ]]; then
                    worktree_launch_agent "$agent"
                else
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        osascript <<EOF
tell application "Terminal"
    do script "cd '$PROJECT_ROOT' && '$AGENT_SCRIPT' $agent"
end tell
EOF
                    else
                        "$AGENT_SCRIPT" "$agent"
                    fi
                fi

                # このタスクが完了するまで監視
                while true; do
                    sleep "$check_interval"
                    local status=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .status' "$TASKS_FILE")
                    if [[ "$status" == "completed" || "$status" == "failed" ]]; then
                        printf "%b" "${CYAN}タスク [#$task_id] が${status}しました${NC}\n"
                        echo ""
                        break
                    fi
                done
            fi
        else
            # 待機中のタスクなし
            clear
            printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            printf "%b" "${CYAN}  $(capitalize_agent "$agent") エージェント自動監視モード${NC}\n"
            printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            echo ""
            printf "%b" "${YELLOW}待機中のタスクはありません${NC}\n"
            printf "%b" "${CYAN}新しいタスクが追加されるのを待機中...${NC}\n"
            echo ""
            printf "%b" "${CYAN}最終更新: $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
        fi

        sleep "$check_interval"
    done
}

# メイン処理
case "${1:-}" in
    status|"")
        show_status
        ;;
    agents)
        show_agents_status
        ;;
    stop)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            echo "使用方法: $0 stop <agent|all>"
            echo ""
            echo "例:"
            echo "  $0 stop frontend   # 特定のエージェントを停止"
            echo "  $0 stop all        # すべてのエージェントを停止"
            exit 1
        fi

        if [[ "$2" == "all" ]]; then
            stop_all_agents
        elif [[ "$2" =~ ^[0-9]+$ ]]; then
            # タスクIDが指定された場合、そのタスクのエージェントを特定して停止
            task_id="$2"
            agent=$(jq -r --argjson id "$task_id" '.tasks[] | select(.id == $id) | .agent' "$TASKS_FILE")
            
            if [[ -n "$agent" && "$agent" != "null" ]]; then
                stop_agent "$agent"
                
                # タスクの状態をstoppedに更新
                jq --argjson id "$task_id" --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                   '(.tasks[] | select(.id == $id)) |= (.status = "stopped" | .updated_at = $date)' \
                   "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"
                
                printf "%b" "${GREEN}✓ タスク #$task_id (エージェント: $agent) を停止しました${NC}\n"
            else
                printf "%b" "${RED}エラー: タスクID #$task_id が見つからないか、エージェントが割り当てられていません${NC}\n"
                return 1
            fi
        else
            stop_agent "$2"
        fi
        ;;
    restart)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            echo "使用方法: $0 restart <agent> [timeout]"
            echo "例:"
            echo "  $0 restart backend       # デフォルトタイムアウトで再起動"
            echo "  $0 restart backend 1200  # タイムアウト1200秒で再起動"
            echo "  $0 restart all           # すべてのエージェントを再起動"
            exit 1
        fi

        # タイムアウト引数のチェック（数値のみ）
        timeout=""
        if [[ -n "$3" ]] && [[ "$3" =~ ^[0-9]+$ ]]; then
            timeout="$3"
        fi

        if [[ "$2" == "all" ]]; then
            # すべてのエージェントを再起動
            agents=("frontend" "backend" "tests" "docs")
            for agent in "${agents[@]}"; do
                restart_agent "$agent" "$timeout"
            done
        else
            restart_agent "$2" "$timeout"
        fi
        ;;
    reset)
        # タスクIDが指定されている場合は個別タスクリセット
        if [[ -n "$2" ]] && [[ "$2" != "--keep-logs" ]]; then
            reset_task "$2"
        else
            # オプション: --keep-logs を指定するとログを保持
            keep_logs="false"
            if [[ "$2" == "--keep-logs" ]]; then
                keep_logs="true"
            fi
            reset_orchestrator "$keep_logs"
        fi
        ;;
    retry)
        # タスクリトライ
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 retry <task_id|all> [max_retries]"
            echo ""
            echo "例:"
            echo "  $0 retry 5        # タスク#5をリトライ（最大3回）"
            echo "  $0 retry 5 5      # タスク#5をリトライ（最大5回）"
            echo "  $0 retry all      # 全失敗タスクをリトライ"
            exit 1
        fi

        max_retries="${3:-3}"

        if [[ "$2" == "all" ]]; then
            retry_all_failed "$max_retries"
        else
            retry_task "$2" "$max_retries"
        fi
        ;;
    parallel)
        # 並列エージェント実行
        shift  # "parallel"をスキップ
        parallel_agents "$@"
        ;;
    remove)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            echo "使用方法: $0 remove <agent>"
            exit 1
        fi

        remove_agent "$2"
        ;;
    list)
        list_running_agents
        ;;
    ps)
        list_running_agents
        ;;
    load)
        if [[ -n "$2" ]]; then
            load_from_json "$2"
        else
            load_from_json
        fi
        ;;
    remove-task|delete-task)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 remove-task <task_id>"
            exit 1
        fi
        remove_task_by_id "$2"
        ;;
    add)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスク説明を指定してください${NC}\n"
            echo "使用方法: $0 add <task> [agent] [priority] [worktree]"
            exit 1
        fi


        # worktreeオプションをチェック
        _use_worktree="false"
        _task_desc="$2"
        _agent="${3:-}"
        _priority="${4:-normal}"
        _dependencies="${5:-[]}"

        # 引数の最後がworktreeの場合
        if [[ "$_task_desc" == "worktree" ]]; then
            printf "%b" "${RED}エラー: タスク説明を指定してください${NC}\n"
            exit 1
        fi
        if [[ "$_agent" == "worktree" ]]; then
            _use_worktree="true"
            _agent=""
        elif [[ "$_priority" == "worktree" ]]; then
            _use_worktree="true"
            _priority="normal"
        elif [[ "$_dependencies" == "worktree" ]]; then
            _use_worktree="true"
            _dependencies="[]"
        fi

        # worktreeモードを設定
        if [[ "$_use_worktree" == "true" ]]; then
            USE_WORKTREE="true"
        fi

        # エージェント指定あり -> 手動モード
        if [[ -n "$_agent" ]]; then
            add_task "$_task_desc" "$_agent" "$_priority" "$_dependencies"
        # エージェント指定なし -> 自動振り分けモード
        else
            add_task_auto "$_task_desc" "$_priority"
        fi
        ;;
    start)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            exit 1
        fi
        start_task "$2"
        ;;
    complete)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            exit 1
        fi
        complete_task "$2" "${3:-}"
        ;;
    fail)
        if [[ -z "$2" || -z "$3" ]]; then
            printf "%b" "${RED}エラー: タスクIDと失敗理由を指定してください${NC}\n"
            exit 1
        fi
        fail_task "$2" "$3"
        ;;
    agent)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            exit 1
        fi
        show_agent_tasks "$2"
        ;;
    next)
        get_next_tasks
        ;;
    launch)
        # worktreeオプションをチェック
        if [[ "$2" == "worktree" ]]; then
            USE_WORKTREE="true"
            printf "%b" "${CYAN}Worktreeモード: 有効${NC}\n"
            echo ""
        fi
        launch_all_pending
        ;;
    monitor)
        monitor_tasks "${2:-5}" "${3:-false}"
        ;;
    monitor-agents)
        monitor_agents "${2:-5}"
        ;;
    wait)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 wait <task_id> [check_interval]"
            exit 1
        fi
        wait_for_dependencies "$2" "${3:-5}"
        ;;
    auto)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            echo "使用方法: $0 auto <agent> [worktree]"
            exit 1
        fi

        # worktreeオプションをチェック
        _agent="$2"
        _use_worktree="false"

        if [[ "$3" == "worktree" ]]; then
            _use_worktree="true"
        fi

        # worktreeモードを一時的に設定
        if [[ "$_use_worktree" == "true" ]]; then
            USE_WORKTREE="true"
            printf "%b" "${CYAN}Worktreeモード: 有効${NC}\n"
            echo ""
        fi

        auto_start_next "$_agent" true
        ;;
    watch)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: エージェント名を指定してください${NC}\n"
            echo "使用方法: $0 watch <agent> [check_interval] [worktree]"
            exit 1
        fi

        # worktreeオプションをチェック
        _agent="$2"
        _check_interval="${3:-10}"
        _use_worktree="false"

        if [[ "$_check_interval" == "worktree" ]]; then
            _use_worktree="true"
            _check_interval="10"
        elif [[ -n "$4" && "$4" == "worktree" ]]; then
            _use_worktree="true"
        fi

        # worktreeモードを一時的に設定
        if [[ "$_use_worktree" == "true" ]]; then
            USE_WORKTREE="true"
            printf "%b" "${CYAN}Worktreeモード: 有効${NC}\n"
            echo ""
        fi

        watch_agent "$_agent" "$_check_interval"
        ;;
    exec)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 exec <task_id> [--watch]"
            exit 1
        fi
        _task_id="$2"
        _watch_mode="false"
        if [[ "$3" == "--watch" ]]; then
            _watch_mode="true"
        fi
        execute_task "$_task_id" "$_watch_mode"
        ;;
    exec-all)
        _watch_mode="false"
        if [[ "$2" == "--watch" ]]; then
            _watch_mode="true"
        fi
        execute_all_pending "$_watch_mode"
        ;;
    worktree)
        case "${2:-}" in
            list)
                worktree_list
                ;;
            create)
                worktree_create "$3"
                ;;
            remove)
                worktree_remove "$3"
                ;;
            cleanup)
                worktree_cleanup
                ;;
            launch)
                worktree_launch_agent "$3"
                ;;
            "")
                worktree_list
                ;;
            *)
                printf "%b" "${RED}エラー: 不明な worktree サブコマンド '$2'${NC}\n"
                echo ""
                echo "使用可能なサブコマンド:"
                echo "  ${GREEN}list${NC}                    Worktree 一覧表示"
                echo "  ${GREEN}create <agent>${NC}          エージェント用 Worktree 作成"
                echo "  ${GREEN}remove <agent>${NC}          Worktree 削除"
                echo "  ${GREEN}cleanup${NC}                 Worktree クリーンアップ"
                echo "  ${GREEN}launch <agent>${NC}          Worktree でエージェント起動"
                exit 1
                ;;
        esac
        ;;
    deps|dependencies)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 deps <task_id>"
            exit 1
        fi
        show_dependencies "$2"
        ;;
    merge|merge-worktree)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: Worktree名またはタスクIDを指定してください${NC}\n"
            echo "使用方法:"
            echo "  $0 merge <worktree_name>"
            echo "  $0 merge <task_id> <agent>"
            exit 1
        fi

        # merge-worktree.shスクリプトを実行
        if [[ -f "$SCRIPT_DIR/merge-worktree.sh" ]]; then
            bash "$SCRIPT_DIR/merge-worktree.sh" "$2" "$3"
        else
            printf "%b" "${RED}エラー: merge-worktree.shが見つかりません${NC}\n"
            exit 1
        fi
        ;;
    lock-status|lock)
        show_lock_status
        ;;
    review)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 review <task_id>"
            exit 1
        fi
        create_review_task "$2"
        ;;
    approve)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 approve <task_id>"
            exit 1
        fi
        approve_review "$2"
        ;;
    reject)
        if [[ -z "$2" || -z "$3" ]]; then
            printf "%b" "${RED}エラー: タスクIDと却下理由を指定してください${NC}\n"
            echo "使用方法: $0 reject <task_id> <reason>"
            exit 1
        fi
        reject_review "$2" "$3"
        ;;
    review-create)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 review-create <task_id>"
            exit 1
        fi
        create_review_task "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    logs)
        _logs_lines=50
        _logs_filter_type=""
        _logs_task_id=""

        # オプション解析
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -n|--lines)
                    _logs_lines="$2"
                    shift 2
                    ;;
                -e|--errors)
                    _logs_filter_type="ERROR"
                    shift
                    ;;
                -t|--task)
                    _logs_task_id="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done

        _log_file="$LOGS_DIR/agent-$(date +"%Y-%m-%d").log"

        if [[ ! -f "$_log_file" ]]; then
            printf "%b" "${YELLOW}ログファイルがありません: $_log_file${NC}\n"

            # 利用可能なログファイルを表示
            if [[ -d "$LOGS_DIR" ]]; then
                _logs_available=$(ls -1 "$LOGS_DIR"/agent-*.log 2>/dev/null)
                if [[ -n "$_logs_available" ]]; then
                    echo ""
                    printf "%b" "${CYAN}利用可能なログファイル:${NC}\n"
                    ls -1t "$LOGS_DIR"/agent-*.log 2>/dev/null | head -5 | while read -r f; do
                        echo "  - $(basename "$f")"
                    done
                fi
            fi
            exit 1
        fi

        printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "%b" "${CYAN}  ログ表示: $(basename "$_log_file")${NC}\n"
        printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        echo ""

        # エージェント生存状態を表示
        PID_DIR="$CLAUDE_DIR/pids"
        agent_count=0
        running_agents=()

        if [[ -d "$PID_DIR" ]]; then
            for pid_file in "$PID_DIR"/*.pid; do
                if [[ -f "$pid_file" ]]; then
                    pid=$(cat "$pid_file" 2>/dev/null)
                    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                        agent=$(basename "$pid_file" .pid)
                        running_agents+=("$agent")
                        agent_count=$((agent_count + 1))
                    fi
                fi
            done
        fi

        printf "%b" "${CYAN}実行中のエージェント:${NC} $agent_count 個\n"
        if [[ $agent_count -gt 0 ]]; then
            for agent in "${running_agents[@]}"; do
                # エージェントの現在のタスクを取得
                current_task=$(jq -r --arg agent "$agent" '.tasks[] | select(.agent == $agent and (.status == "in_progress" or .status == "stopped")) | "\(.id)\t\(.description)\t\(.status)"' "$TASKS_FILE" 2>/dev/null | head -1)
                if [[ -n "$current_task" ]]; then
                    task_id=$(echo "$current_task" | cut -f1)
                    task_desc=$(echo "$current_task" | cut -f2)
                    task_status=$(echo "$current_task" | cut -f3)
                    status_icon=""
                    if [[ "$task_status" == "in_progress" ]]; then
                        status_icon="●"
                    elif [[ "$task_status" == "stopped" ]]; then
                        status_icon="■"
                    fi
                    printf "%b" "  ${MAGENTA}$agent${NC}: $status_icon [$task_id] $task_desc\n"
                else
                    printf "%b" "  ${MAGENTA}$agent${NC}: 待機中\n"
                fi
            done
        fi
        echo ""

        # 最後のログ更新時刻を表示
        last_modified=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$_log_file" 2>/dev/null)
        if [[ -n "$last_modified" ]]; then
            printf "%b" "${CYAN}最終更新:${NC} $last_modified\n"
        fi
        echo ""

        # フィルタリング処理
        if [[ -n "$_logs_task_id" ]]; then
            # タスクIDでフィルタ
            printf "%b" "${YELLOW}タスク #$_logs_task_id のログ（最近${_logs_lines}行）:${NC}\n"
            echo ""
            grep "\[#${_logs_task_id}\]" "$_log_file" | tail -"$_logs_lines"
        elif [[ "$_logs_filter_type" == "ERROR" ]]; then
            # エラーのみ表示
            printf "%b" "${RED}エラーログ（最近${_logs_lines}行）:${NC}\n"
            echo ""
            grep "\[ERROR\]" "$_log_file" | tail -"$_logs_lines"
        else
            # 通常表示
            printf "%b" "${CYAN}最近の${_logs_lines}行:${NC}\n"
            echo ""
            tail -"$_logs_lines" "$_log_file"
        fi
        ;;
    log-tail)
        _log_file="$LOGS_DIR/agent-$(date +"%Y-%m-%d").log"
        if [[ -f "$_log_file" ]]; then
            printf "%b" "${CYAN}ログをリアルタイム監視中 (Ctrl+C で終了)${NC}\n"
            printf "%b" "${CYAN}ファイル: $(basename "$_log_file")${NC}\n"
            echo ""
            tail -f "$_log_file"
        else
            printf "%b" "${YELLOW}ログファイルがありません: $_log_file${NC}\n"

            # 利用可能なログファイルを表示
            if [[ -d "$LOGS_DIR" ]]; then
                _logs_available=$(ls -1 "$LOGS_DIR"/agent-*.log 2>/dev/null)
                if [[ -n "$_logs_available" ]]; then
                    echo ""
                    printf "%b" "${CYAN}利用可能なログファイル:${NC}\n"
                    ls -1t "$LOGS_DIR"/agent-*.log 2>/dev/null | head -5 | while read -r f; do
                        echo "  - $(basename "$f")"
                    done
                fi
            fi
            exit 1
        fi
        ;;
    logs-errors)
        _log_file="$LOGS_DIR/agent-$(date +"%Y-%m-%d").log"
        if [[ -f "$_log_file" ]]; then
            printf "%b" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            printf "%b" "${RED}  エラーログ一覧${NC}\n"
            printf "%b" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
            echo ""

            _logs_error_count=$(grep -c "\[ERROR\]" "$_log_file" 2>/dev/null || echo "0")
            printf "%b" "${YELLOW}エラー数: ${_logs_error_count}${NC}\n"
            echo ""

            grep "\[ERROR\]" "$_log_file" | tail -50
        else
            printf "%b" "${YELLOW}ログファイルがありません: $_log_file${NC}\n"
            exit 1
        fi
        ;;
    review)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 review <task_id>"
            exit 1
        fi

        _task_id="$2"
        jq --argjson id "$_task_id" \
           '(.tasks[] | select(.id == $id)) |= .status = "review_needed"' \
           "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

        orch_log "INFO" "レビュー待ちに移行: [$_task_id]"
        printf "%b" "${BLUE}⏳ タスク #$_task_id をレビュー待ちに移行しました${NC}\n"
        ;;
    approve)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 approve <task_id> [comment]"
            exit 1
        fi

        _task_id="$2"
        _comment="${3:-}"
        approve_review "$_task_id" "$_comment"
        ;;
    reject)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 reject <task_id> <reason>"
            exit 1
        fi

        if [[ -z "$3" ]]; then
            printf "%b" "${RED}エラー: 却下理由を指定してください${NC}\n"
            exit 1
        fi

        _task_id="$2"
        _reason="$3"
        reject_review "$_task_id" "$_reason"
        ;;
    review-create)
        if [[ -z "$2" ]]; then
            printf "%b" "${RED}エラー: タスクIDを指定してください${NC}\n"
            echo "使用方法: $0 review-create <task_id>"
            exit 1
        fi

        _task_id="$2"
        _review_id=$(create_review_task "$_task_id")
        printf "%b" "${GREEN}✓ レビュータスクを作成しました: #$_review_id${NC}\n"
        ;;
    dashboard)
        # Dashboard - Go App
        _bin="$SCRIPT_DIR/../bin/control-center"
        
        if [[ ! -x "$_bin" ]]; then
            printf "%b" "${RED}エラー: control-center バイナリが見つかりません: $_bin${NC}\n"
            exit 1
        fi

        # 引数をそのまま渡す (例: --watch)
        shift # "dashboard" を削除
        "$_bin" "$@"
        ;;
    board|taskboard)
        # TUI Task Board - インタラクティブTUIと同じ（Kanban）を使用
        # 旧 tui-taskboard.sh は日本語表示に問題があるため廃止
        _tui_script="$SCRIPT_DIR/tui-interactive.sh"
        if [[ -f "$_tui_script" ]]; then
            bash "$_tui_script" "$@"
        else
            printf "%b" "${RED}エラー: tui-interactive.sh が見つかりません。${NC}\n"
            exit 1
        fi
        ;;
    logs-tui)
        # TUI Logs - ライブログビューア
        _tui_script="$SCRIPT_DIR/tui-logs.sh"
        shift  # Remove 'logs-tui' from arguments

        if [[ ! -f "$_tui_script" ]]; then
            printf "%b" "${RED}エラー: TUI Logs スクリプトが見つかりません${NC}\n"
            exit 1
        fi

        bash "$_tui_script" "$@"
        ;;
    interactive|i)
        # インタラクティブTUIを起動（Kanban）
        _tui_script="$SCRIPT_DIR/tui-interactive.sh"
        if [[ -f "$_tui_script" ]]; then
            bash "$_tui_script" "$@"
        else
            printf "%b" "${RED}エラー: tui-interactive.sh が見つかりません。${NC}\n"
            exit 1
        fi
        ;;
    *)
        printf "%b" "${RED}エラー: 不明なコマンド '$1'${NC}\n"
        echo ""
        show_help
        exit 1
        ;;
esac
