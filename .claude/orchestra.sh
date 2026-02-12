#!/bin/bash
# orchestra.sh - Claude Orchestra 総合管理エントリーポイント
# ダッシュボードの起動、自動実行モード、ウォッチモードを提供

set -euo pipefail

# スクリプトのディレクトリを取得 (.claude ディレクトリ)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD="$SCRIPT_DIR/scripts/dashboard.sh"
ORCHESTRATOR="$SCRIPT_DIR/scripts/orchestrator.sh"
AGENT_SCRIPT="$SCRIPT_DIR/agent.sh"

# 色定義
COLOR_SUCCESS='\033[38;5;82m'
COLOR_ERROR='\033[38;5;203m'
COLOR_INFO='\033[38;5;33m'
COLOR_WARNING='\033[38;5;214m'
NC='\033[0m'

# 依存関係チェック
check_dependencies() {
    local missing=()
    
    for cmd in jq tput; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "%b" "${COLOR_ERROR}Error: 以下のコマンドが必要です:${NC}\n"
        for cmd in "${missing[@]}"; do
            printf "  - %s\n" "$cmd"
        done
        printf "\n"
        printf "%b" "${COLOR_INFO}インストール方法:${NC}\n"
        printf "  macOS: brew install jq ncurses\n"
        printf "  Ubuntu/Debian: sudo apt-get install jq ncurses-bin\n"
        exit 1
    fi
}

# ダッシュボード表示
show_dashboard() {
    bash "$DASHBOARD"
}

# ヘルプ表示
show_help() {
    cat << 'EOF'
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 🎯 Claude Orchestra - Management Console                   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

使い方:
  bash .claude/orchestra.sh [オプション]

オプション:
  (なし)          対話型ダッシュボードを表示
  --auto          自動実行モードで起動（ワーカー＋ウォッチ）
  --watch         自動更新モードで起動（5秒ごと）
  --help          このヘルプを表示

コマンド例:
  bash .claude/orchestra.sh              # ダッシュボード表示
  bash .claude/orchestra.sh --watch      # 自動更新モード
  bash .claude/orchestra.sh --auto       # 自動実行モード

ダッシュボード内のコマンド:
  [r]efresh      画面を更新
  [w]atch        自動更新の切り替え
  [a]dd          タスクを追加
  [s]tart <id>   エージェントを起動してタスクを開始
  [c]omplete <id> タスクを完了
  [q]uit         終了

詳細: https://github.com/shineos/claude-orchestra
EOF
}

# 自動更新モード
watch_mode() {
    printf "%b" "${COLOR_INFO}自動更新モードを開始します（5秒ごと更新）${NC}\n"
    printf "%b" "${COLOR_WARNING}終了するには Ctrl+C を押してください${NC}\n\n"
    sleep 2
    
    while true; do
        clear
        show_dashboard
        sleep 5
    done
}

# 自動実行モード
auto_mode() {
    printf "%b" "${COLOR_INFO}自動実行モードを開始します${NC}\n"
    printf "%b" "${COLOR_WARNING}バックグラウンドでタスクを自動実行します${NC}\n\n"
    
    # ワーカーをバックグラウンドで起動
    bash "$ORCHESTRATOR" worker &
    WORKER_PID=$!
    
    printf "%b" "${COLOR_SUCCESS}✓ ワーカーを起動しました (PID: ${WORKER_PID})${NC}\n\n"
    sleep 2
    
    # ダッシュボードを自動更新モードで表示
    trap "kill $WORKER_PID 2>/dev/null" EXIT
    watch_mode
}

# メイン処理
main() {
    # 依存関係チェック
    check_dependencies
    
    # 引数処理
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --watch|-w)
            watch_mode
            ;;
        --auto|-a)
            auto_mode
            ;;
        "")
            show_dashboard
            ;;
        *)
            # その他の引数は orchestrator.sh に直接渡す
            bash "$ORCHESTRATOR" "$@"
            exit $?
            ;;
    esac
}

# スクリプト実行
main "$@"
