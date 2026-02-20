#!/bin/bash
# orchestra.sh - Claude Orchestra 総合管理エントリーポイント
# ダッシュボードの起動、自動実行モード、ウォッチモードを提供

set -euo pipefail

# スクリプトのディレクトリを取得 (.claude ディレクトリ)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_BIN="$SCRIPT_DIR/bin/control-center"
ORCHESTRATOR="$SCRIPT_DIR/scripts/orchestrator.sh"
AGENT_SCRIPT="$SCRIPT_DIR/agent.sh"


# --------------------------------------------------------------------------------
# カラー設定
# --------------------------------------------------------------------------------
COLOR_INFO="\033[0;36m"
COLOR_SUCCESS="\033[0;32m"
COLOR_WARNING="\033[0;33m"
COLOR_ERROR="\033[0;31m"
NC="\033[0m"

check_dependencies() {
    # No longer need jq/ncurses for dashboard itself, but orchestrator might need them.
    # Keep checks for now.
    local missing=()
    for cmd in jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    # ...
}

# ダッシュボード表示
show_dashboard() {
    if [[ -x "$DASHBOARD_BIN" ]]; then
        "$DASHBOARD_BIN"
    else
        printf "%b" "${COLOR_ERROR}Error: control-center binary not found at $DASHBOARD_BIN${NC}\n"
        exit 1
    fi
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
        "dashboard")
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
