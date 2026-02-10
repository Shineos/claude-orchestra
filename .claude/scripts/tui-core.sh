#!/bin/bash
# TUI Core Library
#
# TUI共通関数ライブラリ
# 色設定、画面制御、ユーティリティ関数を提供

# =============================================================================
# 色設定 (Claude Code風 256色パレット)
# =============================================================================

# Primary Colors
COLOR_PRIMARY='\033[38;5;33m'      # Blue
COLOR_SECONDARY='\033[38;5;98m'    # Purple
COLOR_SUCCESS='\033[38;5;82m'      # Green
COLOR_WARNING='\033[38;5;214m'     # Orange
COLOR_ERROR='\033[38;5;203m'       # Red
COLOR_INFO='\033[38;5;39m'         # Cyan

# Neutral Colors
COLOR_BG='\033[48;5;236m'          # Dark background
COLOR_FG='\033[38;5;250m'          # Light foreground
COLOR_DIM='\033[38;5;244m'         # Dim text
COLOR_BORDER='\033[38;5;240m'      # Border

# Status Colors
COLOR_PENDING='\033[38;5;244m'     # Gray
COLOR_IN_PROGRESS='\033[38;5;226m' # Yellow
COLOR_REVIEW='\033[38;5;147m'      # Light purple
COLOR_COMPLETED='\033[38;5;82m'    # Green
COLOR_REJECTED='\033[38;5;203m'    # Red

# Agent Colors
COLOR_ARCHITECT='\033[38;5;147m'  # Light purple
COLOR_FRONTEND='\033[38;5;81m'     # Cyan
COLOR_BACKEND='\033[38;5;107m'     # Green
COLOR_TESTER='\033[38;5;229m'      # Pink
COLOR_REVIEWER='\033[38;5;215m'    # Orange
COLOR_DOCS='\033[38;5;244m'        # Gray

# Priority Colors
COLOR_CRITICAL='\033[38;5;203m'    # Red
COLOR_HIGH='\033[38;5;214m'        # Orange
COLOR_NORMAL='\033[38;5;226m'      # Yellow
COLOR_LOW='\033[38;5;82m'          # Green

# Reset & Styles
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
REVERSE='\033[7m'

# =============================================================================
# 画面制御関数
# =============================================================================

# 画面をクリア
tui_clear() {
    tput clear
}

# カーソル位置を保存
tui_save_cursor() {
    tput sc
}

# カーソル位置を復元
tui_restore_cursor() {
    tput rc
}

# カーソルを移動
tui_move() {
    local row=$1
    local col=$2
    tput cup "$row" "$col"
}

# カーソルを非表示
tui_hide_cursor() {
    tput civis
}

# カーソルを表示
tui_show_cursor() {
    tput cnorm
}

# 画面サイズを取得
tui_get_size() {
    echo "$(tput lines) $(tput cols)"
}

tui_get_rows() {
    tput lines
}

tui_get_cols() {
    tput cols
}

# =============================================================================
# 描画プリミティブ
# =============================================================================

# 水平線を描画
tui_hline() {
    local length=$1
    local char="${2:-─}"
    local color="${3:-$COLOR_BORDER}"
    printf "${color}"
    printf "%${length}s" | tr ' ' "$char"
    printf "${NC}"
}

# 垂直線を描画
tui_vline() {
    local length=$1
    local char="${2:-│}"
    local color="${3:-$COLOR_BORDER}"
    local row=0
    while [[ $row -lt $length ]]; do
        printf "${color}${char}${NC}\n"
        ((row++))
    done
}

# ボックスを描画
tui_box() {
    local row=$1
    local col=$2
    local width=$3
    local height=$4
    local title="${5:-}"
    local color="${6:-$COLOR_BORDER}"

    tui_move "$row" "$col"

    # 上辺
    printf "${color}┌"
    tui_hline $((width - 2))
    printf "┐${NC}\n"

    # タイトル行（あれば）
    if [[ -n "$title" ]]; then
        ((row++))
        tui_move "$row" "$col"
        printf "${color}│${NC} ${BOLD}${title}${NC}"
        local title_len=${#title}
        local spaces=$((width - title_len - 3))
        printf "%${spaces}s" " "
        printf "${color}│${NC}\n"
        ((row++))
        tui_move "$row" "$col"
    fi

    # 左右の辺
    local body_row=0
    while [[ $body_row -lt $((height - 2)) ]]; do
        tui_move $((row + body_row + 1)) "$col"
        printf "${color}│${NC}"
        tui_move $((row + body_row + 1)) $((col + width - 1))
        printf "${color}│${NC}\n"
        ((body_row++))
    done

    # 下辺
    tui_move $((row + height - 1)) "$col"
    printf "${color}└"
    tui_hline $((width - 2))
    printf "┘${NC}"
}

# テキストを指定位置に描画
tui_print() {
    local row=$1
    local col=$2
    local text="$3"
    local color="${4:-$NC}"
    tui_move "$row" "$col"
    printf "${color}${text}${NC}"
}

# =============================================================================
# 端末設定管理
# =============================================================================

# 端末の初期設定を保存
declare -g TUI_STTY_SETTINGS=""
declare -g TUI_TERMINAL_INITIALIZED=false

# 端末をTUIモードに設定
tui_init_terminal() {
    if [[ "$TUI_TERMINAL_INITIALIZED" == "true" ]]; then
        return 0
    fi

    # 現在の設定を保存
    TUI_STTY_SETTINGS=$(stty -g)

    # TUI用設定
    stty -echo           # エコー無効化
    stty -icanon         # キャノンカルモード無効化（1文字ずつ入力）
    tui_hide_cursor      # カーソル非表示

    # 終了時のクリーンアップを設定
    trap tui_cleanup_terminal EXIT INT TERM

    TUI_TERMINAL_INITIALIZED=true
}

# 端末設定を復元
tui_cleanup_terminal() {
    if [[ "$TUI_TERMINAL_INITIALIZED" == "false" ]]; then
        return 0
    fi

    # 設定を復元
    if [[ -n "$TUI_STTY_SETTINGS" ]]; then
        stty "$TUI_STTY_SETTINGS" 2>/dev/null
    fi

    tui_show_cursor
    tui_clear
    tui_restore_cursor

    TUI_TERMINAL_INITIALIZED=false
}

# =============================================================================
# 色ユーティリティ
# =============================================================================

# ステータスに応じた色を取得
tui_get_status_color() {
    local status="$1"
    case "$status" in
        pending)
            echo "$COLOR_PENDING"
            ;;
        in_progress)
            echo "$COLOR_IN_PROGRESS"
            ;;
        review_needed)
            echo "$COLOR_REVIEW"
            ;;
        completed)
            echo "$COLOR_COMPLETED"
            ;;
        rejected|failed)
            echo "$COLOR_REJECTED"
            ;;
        stopped)
            echo "$COLOR_WARNING"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# エージェントに応じた色を取得
tui_get_agent_color() {
    local agent="$1"
    case "$agent" in
        architect)
            echo "$COLOR_ARCHITECT"
            ;;
        frontend)
            echo "$COLOR_FRONTEND"
            ;;
        backend)
            echo "$COLOR_BACKEND"
            ;;
        tester|tests)
            echo "$COLOR_TESTER"
            ;;
        reviewer)
            echo "$COLOR_REVIEWER"
            ;;
        docs)
            echo "$COLOR_DOCS"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# 優先度に応じた色を取得
tui_get_priority_color() {
    local priority="$1"
    case "$priority" in
        critical)
            echo "$COLOR_CRITICAL"
            ;;
        high)
            echo "$COLOR_HIGH"
            ;;
        normal|medium)
            echo "$COLOR_NORMAL"
            ;;
        low)
            echo "$COLOR_LOW"
            ;;
        *)
            echo "$NC"
            ;;
    esac
}

# 優先度バッジを取得
tui_get_priority_badge() {
    local priority="$1"
    case "$priority" in
        critical)
            echo "${COLOR_CRITICAL}!!!${NC}"
            ;;
        high)
            echo "${COLOR_HIGH}!!${NC}"
            ;;
        normal|medium)
            echo "${COLOR_NORMAL}-${NC}"
            ;;
        low)
            echo "${COLOR_LOW}↓${NC}"
            ;;
        *)
            echo "?"
            ;;
    esac
}

# ステータスアイコンを取得
tui_get_status_icon() {
    local status="$1"
    local color=$(tui_get_status_color "$status")
    case "$status" in
        pending)
            echo "${color}○${NC}"
            ;;
        in_progress)
            echo "${color}●${NC}"
            ;;
        review_needed)
            echo "${color}◐${NC}"
            ;;
        completed)
            echo "${color}✓${NC}"
            ;;
        rejected|failed)
            echo "${color}✗${NC}"
            ;;
        stopped)
            echo "${color}⏸${NC}"
            ;;
        *)
            echo "?"
            ;;
    esac
}

# =============================================================================
# テキストユーティリティ
# =============================================================================

# テキストを指定幅にトリム
tui_truncate() {
    local text="$1"
    local max_width=$2
    local suffix="${3:-...}"

    if [[ ${#text} -gt $max_width ]]; then
        local available=$((max_width - ${#suffix}))
        echo "${text:0:$available}${suffix}"
    else
        echo "$text"
    fi
}

# テキストを中央揃え
tui_center() {
    local text="$1"
    local width=$2
    local len=${#text}
    local padding=$(( (width - len) / 2 ))
    printf "%${padding}s%s" "" "$text"
}

# =============================================================================
# 進捗バー
# =============================================================================

# 進捗バーを描画
tui_progress_bar() {
    local percentage=$1
    local width=${2:-30}
    local filled_char="${3:-█}"
    local empty_char="${4:-░}"
    local color="${5:-$COLOR_SUCCESS}"

    local filled=$(( width * percentage / 100 ))
    local empty=$(( width - filled ))

    printf "[${color}"
    printf "%${filled}s" | tr ' ' "$filled_char"
    printf "${NC}${COLOR_DIM}"
    printf "%${empty}s" | tr ' ' "$empty_char"
    printf "${NC}] %3d%%" "$percentage"
}

# =============================================================================
# データ取得（orchestrator連携）
# =============================================================================

# タスクファイルを取得
tui_get_tasks_file() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local claude_dir="$(dirname "$script_dir")"
    echo "$claude_dir/tasks.json"
}

# 全タスクを取得
tui_get_tasks() {
    local tasks_file=$(tui_get_tasks_file)
    if [[ ! -f "$tasks_file" ]]; then
        echo "[]"
        return
    fi
    jq '.tasks' "$tasks_file" 2>/dev/null || echo "[]"
}

# ステータス別タスクを取得
tui_get_tasks_by_status() {
    local status="$1"
    local tasks_file=$(tui_get_tasks_file)
    jq -r --arg status "$status" \
        '.tasks[] | select(.status == $status)' \
        "$tasks_file" 2>/dev/null || echo "[]"
}

# タスク統計を取得
tui_get_stats() {
    local tasks_file=$(tui_get_tasks_file)
    jq -r '{
        total: (.tasks | length),
        completed: ([.tasks[] | select(.status == "completed")] | length),
        in_progress: ([.tasks[] | select(.status == "in_progress")] | length),
        pending: ([.tasks[] | select(.status == "pending")] | length),
        review_needed: ([.tasks[] | select(.status == "review_needed")] | length),
        rejected: ([.tasks[] | select(.status == "rejected" or .status == "failed")] | length)
    }' "$tasks_file" 2>/dev/null || echo '{"total":0,"completed":0,"in_progress":0,"pending":0,"review_needed":0,"rejected":0}'
}

# =============================================================================
# エクスポート
# =============================================================================

# このファイルがsourceされた場合、関数をエクスポート
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f tui_clear
    export -f tui_save_cursor
    export -f tui_restore_cursor
    export -f tui_move
    export -f tui_hide_cursor
    export -f tui_show_cursor
    export -f tui_get_size
    export -f tui_get_rows
    export -f tui_get_cols
    export -f tui_hline
    export -f tui_vline
    export -f tui_box
    export -f tui_print
    export -f tui_init_terminal
    export -f tui_cleanup_terminal
    export -f tui_get_status_color
    export -f tui_get_agent_color
    export -f tui_get_priority_color
    export -f tui_get_priority_badge
    export -f tui_get_status_icon
    export -f tui_truncate
    export -f tui_center
    export -f tui_progress_bar
    export -f tui_get_tasks_file
    export -f tui_get_tasks
    export -f tui_get_tasks_by_status
    export -f tui_get_stats
fi
