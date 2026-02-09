#!/bin/bash
# 関連ドキュメント自動更新スクリプト
#
# ファイル変更を検知して関連するドキュメントの更新を促します
#
# 使用方法:
#   ./sync-related-docs.sh <file_path>     # 特定ファイルの変更を処理
#   ./sync-related-docs.sh --git-diff     # 最後のコミットからの変更を処理
#   ./sync-related-docs.sh --watch        # ファイル変更を監視（fswatchが必要）

set -e

# 色設定
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# このスクリプトの場所
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# 関連ドキュメントマッピング定義
# =============================================================================

# ファイルパターンと関連ドキュメントのマッピング
declare -A DOC_RELATIONS=(
    # Prismaスキーマ → テーブル設計書、ER図
    ["schema.prisma"]="docs/database/table-design.md,docs/database/er-diagram.md"
    ["**/schema.prisma"]="docs/database/table-design.md,docs/database/er-diagram.md"

    # API仕様 → API設計書、シーケンス図
    ["spec/api/*.yaml"]="docs/api/api-design.md,docs/sequence/api-flow.md"
    ["spec/api/*.yml"]="docs/api/api-design.md,docs/sequence/api-flow.md"
    ["openapi.yaml"]="docs/api/api-design.md"
    ["openapi.yml"]="docs/api/api-design.md"

    # コンポーネント → コンポーネント図
    ["src/components/**/*.tsx"]="docs/architecture/component-diagram.md"
    ["src/components/**/*.jsx"]="docs/architecture/component-diagram.md"

    # ルーティング → アーキテクチャ図
    ["src/routes/**"]="docs/architecture/architecture-diagram.md"
    ["src/app/**"]="docs/architecture/architecture-diagram.md"
)

# 自動生成ルール（タスク自動作成用）
declare -A AUTO_GENERATE_RULES=(
    ["schema.prisma"]="table-design"
    ["spec/api/*.yaml"]="api-design"
    ["openapi.yaml"]="api-design"
)

# =============================================================================
# 関連ドキュメント検索
# =============================================================================

# パターンマッチング（glob風）
match_pattern() {
    local file="$1"
    local pattern="$2"

    # 単純な文字列比較
    if [[ "$file" == "$pattern" ]]; then
        return 0
    fi

    # ワイルドカードマッチ
    if [[ "$pattern" == *"*"* ]]; then
        local regex
        regex=$(echo "$pattern" | sed 's/\./\\./g' | sed 's/\*/.*/g')
        if [[ "$file" =~ ^$regex$ ]]; then
            return 0
        fi
    fi

    return 1
}

# 関連ドキュメントを取得
get_related_docs() {
    local changed_file="$1"
    local related_docs=""

    # 相対パスに変換
    local rel_file="$changed_file"
    if [[ "$rel_file" == */* ]]; then
        rel_file="${rel_file#*/}"
    fi

    for pattern in "${!DOC_RELATIONS[@]}"; do
        if match_pattern "$rel_file" "$pattern" || match_pattern "$changed_file" "$pattern"; then
            related_docs="${DOC_RELATIONS[$pattern]}"
            break
        fi
    done

    echo "$related_docs"
}

# =============================================================================
# ドキュメント更新チェック
# =============================================================================

check_doc_consistency() {
    local changed_file="$1"
    local related_docs
    related_docs=$(get_related_docs "$changed_file")

    if [[ -z "$related_docs" ]]; then
        return 0
    fi

    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  関連ドキュメントの整合性チェック${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
    printf "%b" "${YELLOW}変更されたファイル:${NC} $changed_file\n"
    echo ""

    local needs_update=false
    local missing_docs=()

    echo "関連ドキュメント:"
    echo "$related_docs" | tr ',' '\n' | while read -r doc; do
        [[ -z "$doc" ]] && continue

        local doc_path="${CLAUDE_DIR}/../${doc}"

        if [[ -f "$doc_path" ]]; then
            local file_mtime=$(stat -f "%m" "$changed_file" 2>/dev/null || stat -c "%Y" "$changed_file" 2>/dev/null)
            local doc_mtime=$(stat -f "%m" "$doc_path" 2>/dev/null || stat -c "%Y" "$doc_path" 2>/dev/null)

            if [[ -n "$file_mtime" ]] && [[ -n "$doc_mtime" ]]; then
                if [[ $file_mtime -gt $doc_mtime ]]; then
                    printf "  ${YELLOW}⚠${NC} ${doc} (${CYAN}要更新${NC})\n"
                    needs_update=true
                else
                    printf "  ${GREEN}✓${NC} ${doc}\n"
                fi
            fi
        else
            printf "  ${RED}✗${NC} ${doc} (${CYAN}未作成${NC})\n"
            missing_docs+=("$doc")
            needs_update=true
        fi
    done
    echo ""

    if [[ "$needs_update" == "true" ]]; then
        printf "%b" "${YELLOW}関連ドキュメントの更新が必要です${NC}\n"
        echo ""
        printf "%b" "${BLUE}次のいずれかの方法で対応してください:${NC}\n"
        echo "  1. テンプレートマネージャーを使用してドキュメントを更新:"
        echo "     ${GREEN}./template-manager.sh generate${NC}"
        echo "  2. Docsエージェントにタスクを追加:"
        echo "     ${GREEN}orch add \"ドキュメント更新: $changed_file の変更を反映\" docs${NC}"
        echo "  3. 手動でドキュメントを更新"
        echo ""

        # 自動タスク追加の確認
        printf "%b" "${YELLOW}Docsエージェントにタスクを追加しますか？ (y/N):${NC} "
        read -r -n 1 response
        echo ""

        if [[ "$response" =~ ^[Yy]$ ]]; then
            add_docs_task "$changed_file" "$related_docs"
        fi
    else
        printf "%b" "${GREEN}すべての関連ドキュメントは最新です${NC}\n"
    fi

    return 0
}

# =============================================================================
# Docsエージェントへのタスク追加
# =============================================================================

add_docs_task() {
    local changed_file="$1"
    local related_docs="$2"

    # orchestrator.shのパス
    local orchestrator="$SCRIPT_DIR/orchestrator.sh"

    if [[ ! -f "$orchestrator" ]]; then
        printf "%b" "${RED}エラー: orchestrator.shが見つかりません${NC}\n"
        return 1
    fi

    # タスク説明を作成
    local task_desc="ドキュメント更新: $changed_file の変更を反映"
    local docs_list=$(echo "$related_docs" | tr ',' '\n' | head -3 | tr '\n' ',' | sed 's/,$//')

    # タスクを追加
    bash "$orchestrator" add "$task_desc" docs normal "[]"

    printf "%b" "${GREEN}✓ タスクを追加しました${NC}\n"
}

# =============================================================================
# Git diff処理
# =============================================================================

process_git_diff() {
    local base_ref="${1:-HEAD~1}"

    printf "%b" "${BLUE}Git差分をチェック中... (${base_ref}からHEAD)${NC}\n"
    echo ""

    local has_changes=false

    # 変更されたファイルをチェック
    git diff --name-only "$base_ref" HEAD 2>/dev/null | while read -r file; do
        [[ -z "$file" ]] && continue

        # ドキュメントファイルはスキップ
        if [[ "$file" == docs/** ]]; then
            continue
        fi

        local related_docs
        related_docs=$(get_related_docs "$file")

        if [[ -n "$related_docs" ]]; then
            check_doc_consistency "$file"
            echo ""
            has_changes=true
        fi
    done

    if [[ "$has_changes" == "false" ]]; then
        printf "%b" "${GREEN}ドキュメント更新が必要なファイルはありませんでした${NC}\n"
    fi
}

# =============================================================================
# 監視モード
# =============================================================================

watch_mode() {
    printf "%b" "${CYAN}ファイル監視モード${NC}\n"
    echo ""

    # fswatchのチェック
    if ! command -v fswatch &> /dev/null; then
        printf "%b" "${RED}エラー: fswatchがインストールされていません${NC}\n"
        echo ""
        echo "macOS: brew install fswatch"
        echo "Linux: sudo apt-get install fswatch"
        return 1
    fi

    printf "%b" "${YELLOW}監視中... (Ctrl+C で終了)${NC}\n"
    echo ""

    # プロジェクトルート
    local project_root="${CLAUDE_DIR}/.."

    # fswatchで監視
    fswatch -o "${project_root}" -r -e "docs/" -e "node_modules/" -e ".git/" | while read -r file; do
        # 相対パスに変換
        local rel_file="${file#$project_root/}"
        rel_file="${rel_file#./}"

        printf "%b" "\n${CYAN}[${rel_file}]${NC} 変更を検出\n"

        local related_docs
        related_docs=$(get_related_docs "$rel_file")

        if [[ -n "$related_docs" ]]; then
            check_doc_consistency "$rel_file"
        fi
    done
}

# =============================================================================
# ヘルプ
# =============================================================================

show_help() {
    cat << EOF
${CYAN}関連ドキュメント同期スクリプト${NC}

${YELLOW}使用方法:${NC}
    $0 <file_path>           # 特定ファイルの変更を処理
    $0 --git-diff [ref]      # Git差分を処理（デフォルト: HEAD~1）
    $0 --watch               # ファイル変更を監視

${YELLOW}例:${NC}
    $0 schema.prisma
    $0 --git-diff
    $0 --git-diff main
    $0 --watch

${YELLOW}説明:${NC}
    ファイル変更を検知し、関連するドキュメントの更新が必要かどうかをチェックします。
    必要に応じてDocsエージェントにタスクを追加できます。
EOF
}

# =============================================================================
# メイン処理
# =============================================================================

case "${1:-}" in
    help|--help|-h|"")
        show_help
        ;;
    --git-diff)
        process_git_diff "${2:-HEAD~1}"
        ;;
    --watch)
        watch_mode
        ;;
    *)
        if [[ -f "$1" ]]; then
            check_doc_consistency "$1"
        else
            printf "%b" "${RED}エラー: ファイルが見つかりません: $1${NC}\n"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
