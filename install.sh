#!/bin/bash
# Claude Code マルチエージェントシステム インストーラー
#
# 使用方法:
#   ./install.sh /path/to/target/project

set -e

# 色設定
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# スクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# テンプレートディレクトリはカレントディレクトリ（リポジトリルート）
TEMPLATE_DIR="$SCRIPT_DIR"

# 引数解析
FORCE=false
TARGET_PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            if [[ -z "$TARGET_PROJECT" ]]; then
                TARGET_PROJECT="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET_PROJECT" ]]; then
    printf "%b" "${RED}エラー: ターゲットプロジェクトのパスを指定してください${NC}\n"
    echo "使用方法: $0 [-f|--force] /path/to/target/project"
    exit 1
fi

if [[ ! -d "$TARGET_PROJECT" ]]; then
    printf "%b" "${RED}エラー: 指定されたパスが存在しません: $TARGET_PROJECT${NC}\n"
    exit 1
fi

printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${CYAN}  Claude Orchestra - インストール${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "%b" "${CYAN}ターゲットプロジェクト:${NC} $TARGET_PROJECT\n"
echo ""

# ターゲットの.claudeディレクトリ
CLAUDE_DIR="$TARGET_PROJECT/.claude"

# 既存チェック
if [[ -d "$CLAUDE_DIR" ]]; then
    printf "%b" "${YELLOW}⚠ .claude ディレクトリは既に存在します${NC}\n"
    if [[ "$FORCE" == true ]]; then
        printf "%b" "${CYAN}--force オプションが指定されたため、上書きします${NC}\n"
        rm -rf "$CLAUDE_DIR"
    else
        read -p "上書きしますか？ (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            printf "%b" "${YELLOW}キャンセルしました${NC}\n"
            exit 0
        fi
        rm -rf "$CLAUDE_DIR"
    fi
fi

# ディレクトリ作成
mkdir -p "$CLAUDE_DIR"
printf "%b" "${GREEN}✓ ディレクトリを作成しました${NC}\n"

# ------------------------------------------------------------------
# 必要なファイルをコピー
# ------------------------------------------------------------------

# 1. agents ディレクトリ
if [[ -d "$TEMPLATE_DIR/agents" ]]; then
    cp -r "$TEMPLATE_DIR/agents" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ agents ディレクトリをコピーしました${NC}\n"
else
    printf "%b" "${RED}エラー: agents ディレクトリが見つかりません${NC}\n"
    exit 1
fi

# 2. scripts ディレクトリ
if [[ -d "$TEMPLATE_DIR/scripts" ]]; then
    cp -r "$TEMPLATE_DIR/scripts" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ scripts ディレクトリをコピーしました${NC}\n"
    
    # 実行権限を付与
    chmod +x "$CLAUDE_DIR/scripts/"*.sh
else
    printf "%b" "${RED}エラー: scripts ディレクトリが見つかりません${NC}\n"
    exit 1
fi

# 3. prompts ディレクトリ
if [[ -d "$TEMPLATE_DIR/prompts" ]]; then
    cp -r "$TEMPLATE_DIR/prompts" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ prompts ディレクトリをコピーしました${NC}\n"
fi

# 4. agent.sh
if [[ -f "$TEMPLATE_DIR/agent.sh" ]]; then
    cp "$TEMPLATE_DIR/agent.sh" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/agent.sh"
    printf "%b" "${GREEN}✓ agent.sh をコピーしました${NC}\n"
else
    printf "%b" "${RED}エラー: agent.sh が見つかりません${NC}\n"
    exit 1
fi

# 5. config.json
if [[ -f "$TEMPLATE_DIR/config.json" ]]; then
    cp "$TEMPLATE_DIR/config.json" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ config.json をコピーしました${NC}\n"
fi

# 6. tasks.json 初期化
echo '{"tasks": [], "last_id": 0}' > "$CLAUDE_DIR/tasks.json"
printf "%b" "${GREEN}✓ tasks.json を初期化しました${NC}\n"

echo ""
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${GREEN}  インストール完了！${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "%b" "${CYAN}📁 ディレクトリ構造:${NC}\n"
echo "  .claude/"
echo "    ├── config.json          # プロジェクト設定"
echo "    ├── tasks.json           # タスク管理データ"
echo "    ├── agents/              # エージェント設定"
echo "    │   ├── orchestrator.json"
echo "    │   ├── frontend.json"
echo "    │   ├── backend.json"
echo "    │   ├── tests.json"
echo "    │   └── docs.json"
echo "    ├── scripts/             # スクリプトディレクトリ"
echo "    │   └── orchestrator.sh  # タスク管理スクリプト"
echo "    └── agent.sh             # エージェント起動スクリプト"
echo ""
printf "%b" "${CYAN}🚀 使用方法:${NC}\n"
echo "  cd $TARGET_PROJECT"
echo "  # タスク管理"
echo "  bash .claude/scripts/orchestrator.sh status"
echo "  bash .claude/scripts/orchestrator.sh add \"タスク名\""
echo "  # エージェント起動"
echo "  bash .claude/agent.sh frontend"
echo ""
