#!/bin/bash
# タスクリーファイル排他制御スクリプト
#
# tasks.jsonへの並列アクセスを防ぐためのロック機構を提供します
#
# 使用方法:
#   source .claude/scripts/task-lock.sh
#   if acquire_lock; then
#     # tasks.jsonを更新
#     release_lock
#   fi

# ロックファイルのパス
TASK_LOCK_FILE="${TASK_LOCK_FILE:-.claude/tasks.lock}"

# ロックタイムアウト（秒）
TASK_LOCK_TIMEOUT="${TASK_LOCK_TIMEOUT:-30}"

# ロック取得時のPIDを保存
_ACQUIRED_LOCK_PID=""

# =============================================================================
# ロック取得関数
# =============================================================================

acquire_lock() {
    local wait_time=0
    local lock_pid=""

    while [[ -f "$TASK_LOCK_FILE" ]]; do
        # ロックファイルのPIDを読み込み
        lock_pid=$(cat "$TASK_LOCK_FILE" 2>/dev/null || echo "")

        # プロセスが存在するか確認
        if [[ -n "$lock_pid" ]]; then
            if ! kill -0 "$lock_pid" 2>/dev/null; then
                # プロセスが存在しない場合、ロックファイルを削除（クリーンアップ）
                echo "警告: 古いロックファイルを検出しました（PID: $lock_pid）"
                rm -f "$TASK_LOCK_FILE"
                break
            fi
        fi

        # タイムアウトチェック
        if [[ $wait_time -ge $TASK_LOCK_TIMEOUT ]]; then
            printf "%b" "${RED}エラー: ロック取得タイムアウト（${TASK_LOCK_TIMEOUT}秒）${NC}\n" >&2
            printf "%b" "${YELLOW}ロックファイル: $TASK_LOCK_FILE${NC}\n" >&2
            printf "%b" "${YELLOW}保持中のPID: $lock_pid${NC}\n" >&2
            return 1
        fi

        # 1秒待機
        sleep 1
        wait_time=$((wait_time + 1))
    done

    # ロックファイルを作成（現在のPIDを記録）
    echo $$ > "$TASK_LOCK_FILE"
    _ACQUIRED_LOCK_PID=$$

    return 0
}

# =============================================================================
# ロック解放関数
# =============================================================================

release_lock() {
    # 自分が取得したロックのみ解放
    if [[ -f "$TASK_LOCK_FILE" ]]; then
        local lock_pid=$(cat "$TASK_LOCK_FILE" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$$" ]] || [[ "$lock_pid" == "$_ACQUIRED_LOCK_PID" ]]; then
            rm -f "$TASK_LOCK_FILE"
        else
            printf "%b" "${YELLOW}警告: ロック解放スキップ（保持者: PID $lock_pid, 自分: $$）${NC}\n" >&2
        fi
    fi
    _ACQUIRED_LOCK_PID=""
}

# =============================================================================
# 強制ロック解放（緊急用）
# =============================================================================

force_release_lock() {
    local lock_pid=""
    if [[ -f "$TASK_LOCK_FILE" ]]; then
        lock_pid=$(cat "$TASK_LOCK_FILE" 2>/dev/null || echo "")
        printf "%b" "${YELLOW}警告: ロックを強制解放します（保持者: PID $lock_pid）${NC}\n" >&2
        rm -f "$TASK_LOCK_FILE"
    fi
    _ACQUIRED_LOCK_PID=""
}

# =============================================================================
# ロック状態表示
# =============================================================================

show_lock_status() {
    if [[ -f "$TASK_LOCK_FILE" ]]; then
        local lock_pid=$(cat "$TASK_LOCK_FILE" 2>/dev/null || echo "")
        local lock_age=0
        if [[ -n "$lock_pid" ]]; then
            # プロセスの存在確認
            if kill -0 "$lock_pid" 2>/dev/null; then
                printf "%b" "${GREEN}ロック状態: 保持中${NC}\n"
                echo "  PID: $lock_pid"
                echo "  ファイル: $TASK_LOCK_FILE"
            else
                printf "%b" "${YELLOW}ロック状態: 保持者が終了しています（クリーンアップ推奨）${NC}\n"
                echo "  旧PID: $lock_pid"
                echo "  ファイル: $TASK_LOCK_FILE"
            fi
        fi
    else
        printf "%b" "${GREEN}ロック状態: 解放中${NC}\n"
    fi
}

# =============================================================================
# トラップハンドラ（スクリプト終了時にロック解放）
# =============================================================================

trap_cleanup_lock() {
    if [[ -n "$_ACQUIRED_LOCK_PID" ]]; then
        release_lock
    fi
}

# トラップを設定（EXIT, INT, TERM シグナル）
trap trap_cleanup_lock EXIT INT TERM

# =============================================================================
# エイリアス（簡易使用）
# =============================================================================

# ロック付きでコマンド実行
with_lock() {
    if acquire_lock; then
        "$@"
        local exit_code=$?
        release_lock
        return $exit_code
    else
        return 1
    fi
}
