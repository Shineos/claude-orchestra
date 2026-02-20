#!/bin/bash
# プロジェクト初期化スクリプト
#
# このスクリプトをプロジェクトルートにコピーして実行すると、
# マルチエージェントシステムがセットアップされます
#
# 使用方法:
#   1. このスクリプトをプロジェクトルートにコピー
#   2. chmod +x init-project.sh
#   3. ./init-project.sh
#
# または、bashで直接実行:
#   bash init-project.sh

set -e

# 色設定
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

# printf を使用した色出力関数（sh/bash互換）
echo_color() {
    local color_code="$1"
    shift
    printf "%b%s%b\n" "$color_code" "$*" "$NC"
}

# 現在のディレクトリ（プロジェクトルート）
PROJECT_ROOT="$(pwd)"

# .claude ディレクトリパス
CLAUDE_DIR="$PROJECT_ROOT/.claude"

# スクリプトのディレクトリ（init.shの場所）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${CYAN}  Claude Code マルチエージェントシステム - プロジェクト初期化${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "%b" "${CYAN}プロジェクトルート:${NC} $PROJECT_ROOT\n"
echo ""

# 既存チェック
if [[ -d "$CLAUDE_DIR" ]]; then
    printf "%b" "${YELLOW}⚠ .claude ディレクトリは既に存在します${NC}\n"
    read -p "上書きしますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        printf "%b" "${YELLOW}初期化を中止しました${NC}\n"
        exit 0
    fi
    rm -rf "$CLAUDE_DIR"
fi

# ディレクトリ構造作成
printf "%b" "${CYAN}ディレクトリ構造を作成中...${NC}\n"
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$CLAUDE_DIR/scripts"
mkdir -p "$CLAUDE_DIR/tasks"

# プロジェクト設定ファイル作成
cat > "$CLAUDE_DIR/config.json" << EOF
{
  "project_name": "$(basename "$PROJECT_ROOT")",
  "project_root": "$PROJECT_ROOT",
  "initialized_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "agents": {
    "orchestrator": {
      "enabled": true,
      "auto_monitor": true
    },
    "frontend": {
      "enabled": true,
      "framework": "detect"
    },
    "backend": {
      "enabled": true,
      "language": "detect"
    },
    "tests": {
      "enabled": true,
      "framework": "detect"
    },
    "docs": {
      "enabled": true
    }
  }
}
EOF

# タスク管理初期化
cat > "$CLAUDE_DIR/tasks.json" << 'EOF'
{
  "tasks": [],
  "last_id": 0
}
EOF

# .gitignore に追加
if [[ -f "$PROJECT_ROOT/.gitignore" ]]; then
    if ! grep -q "\.claude/tasks\.json" "$PROJECT_ROOT/.gitignore"; then
        echo "" >> "$PROJECT_ROOT/.gitignore"
        echo "# Claude Code マルチエージェントシステム" >> "$PROJECT_ROOT/.gitignore"
        echo ".claude/tasks.json" >> "$PROJECT_ROOT/.gitignore"
        echo ".claude/worktrees/" >> "$PROJECT_ROOT/.gitignore"
        printf "%b" "${GREEN}✓ .gitignore に追加しました${NC}\n"
    fi
fi

printf "%b" "${GREEN}✓ ディレクトリ構造を作成しました${NC}\n"
echo ""

# エージェント設定をコピー
printf "%b" "${CYAN}エージェント設定を配置中...${NC}\n"

# Orchestrator
cat > "$CLAUDE_DIR/agents/orchestrator.json" << 'EOF'
{
  "name": "Orchestrator",
  "role": "coordinator",
  "description": "全エージェントの調整、タスク配分、進捗管理を行います",
  "capabilities": [
    "task_breakdown",
    "agent_coordination",
    "progress_tracking",
    "conflict_resolution",
    "priority_management"
  ],
  "system_prompt": "あなたはOrchestratorエージェントです。以下の役割を担います：\n\n1. **エージェント調整**: 適切な専門エージェントにタスクを割り振る\n2. **進捗追跡**: 全てのタスクとエージェントの状態を監視\n3. **競合解決**: エージェント間の競合を解決\n4. **依存管理**: タスクの依存関係に基づいて実行順序を管理\n5. **品質ゲート**: タスク完了時に品質を確認\n\n直接コードを書くのではなく、専門エージェントにタスクを委譲し、結果を統合してください。\n\nユーザーからのリクエスト時：\n- サブタスクに分解\n- 各サブタスクを担当するエージェントを特定\n- 依存関係を含むタスク計画を作成\n- 実行を監視し問題を処理\n- 結果をユーザーに要約\n\n常に明確に把握しておくこと：\n- 進行中のタスク\n- 各エージェントの作業内容\n- 存在するブロッカー\n- 完了した項目",
  "interacts_with": ["frontend", "backend", "tests", "docs"],
  "priority": 1
}
EOF

# Frontend
cat > "$CLAUDE_DIR/agents/frontend.json" << 'EOF'
{
  "name": "Frontend",
  "role": "specialist",
  "description": "UIコンポーネント、スタイリング、ユーザー操作を扱います",
  "capabilities": [
    "component_development",
    "styling",
    "state_management",
    "responsive_design",
    "accessibility",
    "performance_optimization"
  ],
  "system_prompt": "あなたはFrontend専門エージェントです。以下の役割を担います：\n\n1. **UI実装**: レスポンシブでアクセシブルなUIを構築\n2. **コンポーネント設計**: 再利用可能なコンポーネント階層を設計\n3. **ステート管理**: クライアント側ステートソリューションを実装\n4. **スタイリング**: 一貫性のあるデザインシステムを適用\n5. **UX**: スムーズな操作とフィードバックを保証\n\n技術的焦点：\n- フレームワーク: React, Vue, Svelte, vanilla JavaScript\n- スタイリング: CSS, Tailwind, styled-components など\n- ステート: Redux, Zustand, Context, signals\n- パフォーマンス: コード分割、遅延ロード、最適化\n\n作業時：\n- 既存のプロジェクト規約に従う\n- アクセシビリティを保証（WCAGガイドライン）\n- コンポーネントを視覚的・機能的にテスト\n- 新しいコンポーネントやパターンをドキュメント化\n- ブロッカーをOrchestratorに報告\n\nクライアント側のコードのみを担当。サーバー側ロジックはBackendエージェントに委譲。",
  "file_patterns": [
    "src/**/*.{tsx,ts,jsx,js,vue,svelte}",
    "components/**/*",
    "styles/**/*",
    "public/**/*",
    "app/**/*",
    "pages/**/*"
  ],
  "interacts_with": ["orchestrator", "backend", "tests"],
  "priority": 2
}
EOF

# Backend
cat > "$CLAUDE_DIR/agents/backend.json" << 'EOF'
{
  "name": "Backend",
  "role": "specialist",
  "description": "API、データベース操作、ビジネスロジックを扱います",
  "capabilities": [
    "api_development",
    "database_design",
    "authentication",
    "business_logic",
    "performance_optimization",
    "security"
  ],
  "system_prompt": "あなたはBackend専門エージェントです。以下の役割を担います：\n\n1. **API開発**: REST/GraphQL APIを設計・実装\n2. **データベース**: スキーマ設計、クエリ作成、移行管理\n3. **認証**: セキュアな認証フローを実装（JWT, OAuth, セッション）\n4. **ビジネスロジック**: コアアプリケーションロジックをサーバー側で実装\n5. **セキュリティ**: データ検証、サニタイズ、セキュア practices を保証\n\n技術的焦点：\n- 言語: Node.js, Python, Go, Rust, Java\n- フレームワーク: Express, FastAPI, Django, Spring\n- データベース: PostgreSQL, MongoDB, Redis など\n- セキュリティ: OWASP Top 10, 入力検証, 暗号化\n\n作業時：\n- REST/GraphQLベストプラクティスに従う\n- 適切なエラーハンドリングとロギングを実装\n- 全ての入力をバリデーション\n- SQLインジェクション防止のためパラメータ化クエリを使用\n- APIエンドポイントをドキュメント化\n- スケーラビリティとパフォーマンスを考慮\n- ブロッカーをOrchestratorに報告\n\nサーバー側のコードのみを担当。クライアント側のコードはFrontendエージェントに委譲。",
  "file_patterns": [
    "api/**/*",
    "server/**/*",
    "backend/**/*",
    "db/**/*",
    "models/**/*",
    "controllers/**/*",
    "services/**/*",
    "lib/**/*"
  ],
  "interacts_with": ["orchestrator", "frontend", "tests"],
  "priority": 2
}
EOF

# Tests
cat > "$CLAUDE_DIR/agents/tests.json" << 'EOF'
{
  "name": "Tests",
  "role": "specialist",
  "description": "テスト作成、実行、品質保証を担当します",
  "capabilities": [
    "unit_testing",
    "integration_testing",
    "e2e_testing",
    "test_coverage_analysis",
    "tdd_advocacy",
    "quality_assurance"
  ],
  "system_prompt": "あなたはテスト専門エージェントです。以下の役割を担います：\n\n1. **テスト作成**: 新規・既存コードの包括的テストを作成\n2. **カバレッジ**: テストカバレッジメトリクスを監視・改善\n3. **品質ゲート**: マージ前にコードが品質基準を満たすことを保証\n4. **TDD推奨**: テスト駆動開発 practices を推奨\n5. **バグ再現**: 報告されたバグを再現するテストを作成\n\n技術的焦点：\n- 単体テスト: Jest, Vitest, pytest, JUnit\n- 結合テスト: Supertest, pytest-django\n- E2E: Playwright, Cypress, Puppeteer\n- カバレッジ: Istanbul, pytest-cov, JaCoCo\n- モッキング: Mock Service Worker, pytest-mock\n\n作業時：\n- 実装と同時か前にテストを作成（TDD）\n- 重要なパスを優先し高カバレッジを目指す\n- エッジケースとエラー条件をテスト\n- 明確なテスト名と説明を使用\n- 外部依存を適切にモック\n- 不安定なテストをOrchestratorに報告\n- テストパターンと規約をドキュメント化\n\n全エージェントと連携し、出力が適切にテストされることを保証。",
  "file_patterns": [
    "**/*.test.{ts,js,py,java,go}",
    "**/*.spec.{ts,js,py,java,go}",
    "__tests__/**/*",
    "tests/**/*",
    "test/**/*",
    "e2e/**/*",
    "cypress/**/*",
    "playwright/**/*"
  ],
  "interacts_with": ["orchestrator", "frontend", "backend"],
  "priority": 3
}
EOF

# Docs
cat > "$CLAUDE_DIR/agents/docs.json" << 'EOF'
{
  "name": "Docs",
  "role": "specialist",
  "description": "APIドキュメント、ユーザーガイド、技術仕様書を作成します",
  "capabilities": [
    "api_documentation",
    "user_guides",
    "technical_specifications",
    "readme_maintenance",
    "code_comments",
    "diagrams"
  ],
  "system_prompt": "あなたはドキュメント専門エージェントです。以下の役割を担います：\n\n1. **APIドキュメント**: エンドポイント、パラメータ、レスポンスをドキュメント化\n2. **ユーザーガイド**: 明確なユーザー向けドキュメントを作成\n3. **技術仕様**: アーキテクチャドキュメントと設計仕様書を作成\n4. **README管理**: プロジェクトREADMEを最新に保つ\n5. **コードコメント**: コードが自己文書化されるよう明確なコメントを保証\n\n技術的焦点：\n- フォーマット: Markdown, OpenAPI/Swagger, JSDoc, Docstrings\n- ツール: Docusaurus, GitBook, MkDocs, TypeDoc\n- 図: Mermaid, PlantUML, Draw.io\n\n作業時：\n- 明確で簡潔なドキュメントを作成\n- ドキュメントとコード変更を同期\n- 例とコードスニペットを使用\n- エッジケースと注意点をドキュメント化\n- 一貫したフォーマットを維持\n- ドキュメントのギャップをOrchestratorに報告\n\n全エージェントと連携し、出力をドキュメント化し、プロジェクトに包括的で保守可能なドキュメントがあることを保証。",
  "file_patterns": [
    "docs/**/*",
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "**/*.md",
    "api-docs/**/*"
  ],
  "interacts_with": ["orchestrator", "frontend", "backend", "tests"],
  "priority": 4
}
EOF

printf "%b" "${GREEN}✓ エージェント設定を配置しました${NC}\n"
echo ""

# 簡易起動スクリプト作成
cat > "$CLAUDE_DIR/agent.sh" << 'EOF'
#!/bin/bash
# エージェント簡易起動スクリプト

CLAUDE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$CLAUDE_DIR")"

# エージェント読み込み
load_agent() {
    local agent=$1
    local agent_file="$CLAUDE_DIR/agents/${agent}.json"
    if [[ -f "$agent_file" ]]; then
        jq -r '.system_prompt' "$agent_file" 2>/dev/null
    else
        echo "エージェント設定が見つかりません: $agent"
        exit 1
    fi
}

case "${1:-}" in
    orchestrator|frontend|backend|tests|docs)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  エージェント: $1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        load_agent "$1"
        echo ""
        echo "Claude Codeを起動します..."
        cd "$PROJECT_ROOT" && exec claude
        ;;
    *)
        echo "使用方法: agent.sh <エージェント名>"
        echo ""
        echo "利用可能なエージェント:"
        echo "  - orchestrator  全体調整"
        echo "  - frontend      フロントエンド"
        echo "  - backend       バックエンド"
        echo "  - tests         テスト"
        echo "  - docs          ドキュメント"
        exit 1
        ;;
esac
EOF

chmod +x "$CLAUDE_DIR/agent.sh"

# orchestra.sh (簡易版エントリーポイント) 作成
cat > "$CLAUDE_DIR/orchestra.sh" << 'EOF'
#!/bin/bash
# Claude Orchestra 簡易エントリーポイント

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$SCRIPT_DIR/scripts/dashboard.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Orchestra - Management Console"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ -f "$DASHBOARD" ]]; then
    bash "$DASHBOARD"
else
    echo "エラー: ダッシュボードスクリプトが見つかりません: $DASHBOARD"
    exit 1
fi
EOF

chmod +x "$CLAUDE_DIR/orchestra.sh"

printf "%b" "${GREEN}✓ 起動スクリプトを作成しました${NC}\n"
echo ""

# orchestrator.sh をスクリプトディレクトリにコピー
if [[ -f "$SCRIPT_DIR/orchestrator.sh" ]]; then
    cp "$SCRIPT_DIR/orchestrator.sh" "$CLAUDE_DIR/scripts/orchestrator.sh"
    chmod +x "$CLAUDE_DIR/scripts/orchestrator.sh"
    printf "%b" "${GREEN}✓ Orchestratorスクリプトをコピーしました${NC}\n"
else
    # フォールバック: 組み込み版を作成
    cat > "$CLAUDE_DIR/scripts/orchestrator.sh" << 'EOFORCH'
#!/bin/bash
# Orchestrator - タスク管理・モニタリング
# 詳細は GitHub の最新版を使用してください

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
TASKS_FILE="$CLAUDE_DIR/tasks.json"

# 色設定
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

# 初期化
init_tasks() {
    if [[ ! -f "$TASKS_FILE" ]]; then
        echo '{"tasks": [], "last_id": 0}' > "$TASKS_FILE"
    fi
}

# タスク追加
add_task() {
    local task_desc="$1"
    local agent="$2"
    local priority="${3:-normal}"

    init_tasks
    local last_id=$(jq -r '.last_id' "$TASKS_FILE")
    local task_id=$((last_id + 1))
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local new_task=$(cat <<EOF
{
  "id": $task_id,
  "description": "$task_desc",
  "agent": "$agent",
  "status": "pending",
  "priority": "$priority",
  "created_at": "$timestamp",
  "updated_at": "$timestamp"
}
EOF
)

    jq --argjson new_task "$new_task" --argjson id "$task_id" \
       '.tasks += [$new_task] | .last_id = $id' \
       "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE"

    printf "%b" "${GREEN}✓ タスク追加 [ID: $task_id]${NC} $task_desc\n"
}

# タスク状況表示
show_status() {
    init_tasks
    local total=$(jq '.tasks | length' "$TASKS_FILE")
    local pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "$TASKS_FILE")
    local in_progress=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$TASKS_FILE")
    local completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$TASKS_FILE")

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  タスク状況${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf " 全体:%d 未着手:%b%d%b 実行中:%b%d%b 完了:%b%d%b\n" "$total" "$YELLOW" "$pending" "$NC" "$BLUE" "$in_progress" "$NC" "$GREEN" "$completed" "$NC"
    echo ""

    jq -r '.tasks[] | "\(.id)\t\(.status)\t\(.agent)\t\(.description)"' "$TASKS_FILE" 2>/dev/null | \
    while IFS=$'\t' read -r id status agent desc; do
        local icon="○"
        [[ "$status" == "in_progress" ]] && icon="●"
        [[ "$status" == "completed" ]] && icon="✓"
        echo " [$icon] [#$id] ${agent}: ${desc}"
    done
}

case "${1:-}" in
    status|"") show_status ;;
    add) add_task "$2" "$3" "${4:-normal}" ;;
    start) jq --argjson id "$2" '.tasks |= map(if .id == $id then .status = "in_progress" else . end)' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE" && echo "✓ タスク開始 [#$2]" ;;
    complete) jq --argjson id "$2" '.tasks |= map(if .id == $id then .status = "completed" else . end)' "$TASKS_FILE" > "${TASKS_FILE}.tmp" && mv "${TASKS_FILE}.tmp" "$TASKS_FILE" && echo "✓ タスク完了 [#$2]" ;;
    *) echo "使用方法: orchestrator.sh [status|add|start|complete]" ;;
esac
EOFORCH

    chmod +x "$CLAUDE_DIR/scripts/orchestrator.sh"
    printf "%b" "${GREEN}✓ Orchestratorスクリプトを作成しました${NC}\n"
fi

echo ""

# 完了メッセージ
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${GREEN}  初期化完了！${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "%b" "${CYAN}📁 作成されたファイル:${NC}\n"
echo "  .claude/
    ├── orchestra.sh         # 総合管理エントリーポイント
    ├── agent.sh             # エージェント起動スクリプト
    ├── config.json          # プロジェクト設定
    ├── tasks.json           # タスク管理データ
    ├── agents/              # エージェント設定
    └── scripts/             # スクリプトディレクトリ

🚀 使用方法:
  # 管理コンソール（ダッシュボード）を起動
  bash .claude/orchestra.sh

  # 特定のエージェントを直接起動
  bash .claude/agent.sh frontend

💡 便利なエイリアス:
  alias orch="bash ./.claude/orchestra.sh"
  alias agent="bash ./.claude/agent.sh"
"
echo ""
