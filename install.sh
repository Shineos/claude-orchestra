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
if [[ -d "$TEMPLATE_DIR/.claude/agents" ]]; then
    cp -r "$TEMPLATE_DIR/.claude/agents" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ agents ディレクトリをコピーしました${NC}\n"
else
    printf "%b" "${RED}エラー: agents ディレクトリが見つかりません${NC}\n"
    exit 1
fi

# 2. scripts ディレクトリ
if [[ -d "$TEMPLATE_DIR/.claude/scripts" ]]; then
    cp -r "$TEMPLATE_DIR/.claude/scripts" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ scripts ディレクトリをコピーしました${NC}\n"

    # 実行権限を付与
    chmod +x "$CLAUDE_DIR/scripts/"*.sh
else
    printf "%b" "${RED}エラー: scripts ディレクトリが見つかりません${NC}\n"
    exit 1
fi

# 3. prompts ディレクトリ
if [[ -d "$TEMPLATE_DIR/.claude/prompts" ]]; then
    cp -r "$TEMPLATE_DIR/.claude/prompts" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ prompts ディレクトリをコピーしました${NC}\n"
fi

# 4. agent.sh
if [[ -f "$TEMPLATE_DIR/.claude/agent.sh" ]]; then
    cp "$TEMPLATE_DIR/.claude/agent.sh" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/agent.sh"
    printf "%b" "${GREEN}✓ agent.sh をコピーしました${NC}\n"
else
    printf "%b" "${RED}エラー: agent.sh が見つかりません${NC}\n"
    exit 1
fi

# 5. orchestra.sh (メインエントリーポイント)
if [[ -f "$TEMPLATE_DIR/.claude/orchestra.sh" ]]; then
    cp "$TEMPLATE_DIR/.claude/orchestra.sh" "$CLAUDE_DIR/"
    chmod +x "$CLAUDE_DIR/orchestra.sh"
    printf "%b" "${GREEN}✓ orchestra.sh をコピーしました${NC}\n"
fi

# 6. config.json
if [[ -f "$TEMPLATE_DIR/config.json" ]]; then
    cp "$TEMPLATE_DIR/config.json" "$CLAUDE_DIR/"
    printf "%b" "${GREEN}✓ config.json をコピーしました${NC}\n"
fi

# 7. tasks.json 初期化
if [[ ! -f "$CLAUDE_DIR/tasks.json" ]]; then
    if [[ -f "$TEMPLATE_DIR/.claude/tasks.json.example" ]]; then
        cp "$TEMPLATE_DIR/.claude/tasks.json.example" "$CLAUDE_DIR/tasks.json"
        printf "%b" "${GREEN}✓ tasks.json.example から初期化しました${NC}\n"
    else
        echo '{"tasks": [], "last_id": 0}' > "$CLAUDE_DIR/tasks.json"
        printf "%b" "${GREEN}✓ tasks.json を初期化しました${NC}\n"
    fi
fi

# 8. approvals.json 初期化
if [[ ! -f "$CLAUDE_DIR/approvals.json" ]]; then
    echo '{"approvals": [], "last_id": 0}' > "$CLAUDE_DIR/approvals.json"
    printf "%b" "${GREEN}✓ approvals.json を初期化しました${NC}\n"
fi

# 9. control-center バイナリ
mkdir -p "$CLAUDE_DIR/bin"

# OS/Arch 検出
OS="$(uname -s)"
ARCH="$(uname -m)"
BINARY_NAME=""

case "$OS" in
    Darwin)
        if [[ "$ARCH" == "arm64" ]]; then
            BINARY_NAME="control-center-darwin-arm64"
        else
            BINARY_NAME="control-center-darwin-amd64"
        fi
        ;;
    Linux)
        if [[ "$ARCH" == "x86_64" ]]; then
            BINARY_NAME="control-center-linux-amd64"
        else
            # Fallback or error
            printf "%b" "${YELLOW}⚠ 未サポートのアーキテクチャ: $OS/$ARCH${NC}\n"
        fi
        ;;
    *)
        printf "%b" "${YELLOW}⚠ 未サポートのOS: $OS${NC}\n"
        ;;
esac

INSTALLED=false
if [[ -n "$BINARY_NAME" ]]; then
    # bin/ ディレクトリにあるかチェック（package.sh構成）
    if [[ -f "$TEMPLATE_DIR/bin/$BINARY_NAME" ]]; then
        cp "$TEMPLATE_DIR/bin/$BINARY_NAME" "$CLAUDE_DIR/bin/control-center"
        INSTALLED=true
    # ルートにあるかチェック（開発環境/旧構成）
    elif [[ -f "$TEMPLATE_DIR/$BINARY_NAME" ]]; then
        cp "$TEMPLATE_DIR/$BINARY_NAME" "$CLAUDE_DIR/bin/control-center"
        INSTALLED=true
    # control-center そのものがあるかチェック（手動ビルド）
    elif [[ -f "$TEMPLATE_DIR/control-center" ]]; then
        cp "$TEMPLATE_DIR/control-center" "$CLAUDE_DIR/bin/"
        INSTALLED=true
    fi
fi

if [[ "$INSTALLED" == "true" ]]; then
    chmod +x "$CLAUDE_DIR/bin/control-center"
    printf "%b" "${GREEN}✓ control-center バイナリをインストールしました ($BINARY_NAME)${NC}\n"
else
    printf "%b" "${YELLOW}⚠ control-center バイナリが見つかりません (make buildを実行してください)${NC}\n"
    printf "%b" "${YELLOW}  期待されるバイナリ名: $BINARY_NAME${NC}\n"
fi

echo ""
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${GREEN}  インストール完了！${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "%b" "${CYAN}📁 ディレクトリ構造:${NC}\n"
echo "  .claude/
    ├── orchestra.sh         # 総合管理エントリーポイント（推奨）
    ├── agent.sh             # エージェント起動スクリプト
    ├── config.json          # プロジェクト設定
    ├── tasks.json           # タスク管理データ
    ├── agents/              # エージェント定義集
    ├── prompts/             # システムプロンプト集
    └── scripts/             # ユーティリティスクリプト群
        └── orchestrator.sh  # タスク管理エンジン

Internal storage:
    ├── tasks/               # 各タスクの作業ディレクトリ
    └── logs/                # 実行ログ

🚀 使用方法:
  cd $TARGET_PROJECT

  # 管理コンソール（ダッシュボード）を起動
  bash .claude/orchestra.sh

  # 自動実行モードで起動
  bash .claude/orchestra.sh --auto
"
echo ""
