#!/bin/bash
# Worktreeマージスクリプト
#
# レビュー承認後、Worktreeの変更をメインブランチにマージします
#
# 使用方法:
#   ./merge-worktree.sh <worktree_name>
#   ./merge-worktree.sh <task_id> <agent>

set -e

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# =============================================================================
# ヘルプ
# =============================================================================

show_help() {
    cat << EOF
${CYAN}Worktreeマージスクリプト${NC}

${YELLOW}使用方法:${NC}
    $0 <worktree_name>
    $0 <task_id> <agent>

${YELLOW}例:${NC}
    $0 frontend-task-2
    $0 2 frontend

${YELLOW}説明:${NC}
    レビュー承認後、Worktreeの変更をメインブランチにマージします。
    マージ完了後、Worktreeは削除されます。
EOF
}

# =============================================================================
# マージ処理
# =============================================================================

merge_worktree() {
    local worktree_name="$1"
    local worktree_path="$SCRIPT_DIR/worktrees/$worktree_name"

    # Worktreeが存在するか確認
    if [[ ! -d "$worktree_path" ]]; then
        printf "%b" "${RED}エラー: Worktreeが見つかりません: $worktree_path${NC}\n"
        return 1
    fi

    # Worktreeブランチが存在するか確認
    if ! git show-ref --verify --quiet "refs/heads/$worktree_name"; then
        printf "%b" "${RED}エラー: ブランチが見つかりません: $worktree_name${NC}\n"
        return 1
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  Worktreeマージ${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}Worktree:${NC} $worktree_name${NC}\n"
    printf "%b" "${YELLOW}パス:${NC} $worktree_path${NC}\n"
    echo ""

    # 変更内容を表示
    printf "%b" "${BLUE}変更内容:${NC}\n"
    git diff "main...$worktree_name" --stat || true
    echo ""

    # 確認プロンプト
    printf "%b" "${YELLOW}この変更をマージしますか？ (y/N):${NC} "
    read -r -n 1 response
    echo ""

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        printf "%b" "${YELLOW}マージをキャンセルしました${NC}\n"
        return 0
    fi

    # メインブランチに切り替え
    printf "%b" "${BLUE}メインブランチに切り替え中...${NC}\n"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || {
        printf "%b" "${RED}エラー: メインブランチが見つかりません${NC}\n"
        return 1
    }

    # Worktreeブランチをマージ（--no-ffでマージコミットを作成）
    printf "%b" "${BLUE}マージ実行中...${NC}\n"
    if git merge --no-ff "$worktree_name" -m "Merge $worktree_name

Review approved and merged from worktree."; then
        printf "%b" "${GREEN}✓ マージ成功${NC}\n"
    else
        printf "%b" "${RED}✗ マージ失敗${NC}\n"
        printf "%b" "${YELLOW}競合を解決してから再度実行してください${NC}\n"
        return 1
    fi

    # Worktreeを削除
    printf "%b" "${BLUE}Worktree削除中...${NC}\n"

    # ワーキングツリーを削除
    git worktree remove "$worktree_path" 2>/dev/null || rm -rf "$worktree_path"

    # ブランチを削除
    git branch -d "$worktree_name" 2>/dev/null || true

    printf "%b" "${GREEN}✓ Worktree削除完了${NC}\n"
    echo ""

    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${GREEN}マージ完了: $worktree_name${NC}\n"
    printf "%b" "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# =============================================================================
# タスクIDとエージェントからWorktree名を生成
# ==============================================================================

get_worktree_name() {
    local task_id="$1"
    local agent="$2"
    echo "${agent}-task-${task_id}"
}

# =============================================================================
# メイン処理
# ==============================================================================

WORKTREE_NAME=""
TASK_ID=""
AGENT=""

case "$1" in
    help|--help|-h|"")
        show_help
        exit 0
        ;;
    *)
        # 引数の数で判定
        if [[ $# -eq 1 ]]; then
            # 直接Worktree名を指定
            WORKTREE_NAME="$1"
        elif [[ $# -eq 2 ]]; then
            # タスクIDとエージェントを指定
            TASK_ID="$1"
            AGENT="$2"
            WORKTREE_NAME=$(get_worktree_name "$TASK_ID" "$AGENT")
        else
            printf "%b" "${RED}エラー: 不正な引数${NC}\n"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac

merge_worktree "$WORKTREE_NAME"
