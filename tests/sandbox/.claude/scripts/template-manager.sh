#!/bin/bash
# ドキュメントテンプレート管理スクリプト
#
# テンプレートを使用して統一されたフォーマットでドキュメントを生成します
#
# 使用方法:
#   ./template-manager.sh list                    # テンプレート一覧を表示
#   ./template-manager.sh generate                # インタラクティブモードで生成
#   ./template-manager.sh generate <template> <output>  # 直接指定

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

# テンプレートディレクトリ
TEMPLATES_DIR="$CLAUDE_DIR/templates"
CUSTOM_TEMPLATES_DIR="$CLAUDE_DIR/custom-templates"

# ドキュメント出力ディレクトリ
DOCS_DIR="$CLAUDE_DIR/../docs"

# =============================================================================
# ヘルプ
# =============================================================================

show_help() {
    cat << EOF
${CYAN}ドキュメントテンプレート管理ツール${NC}

${YELLOW}使用方法:${NC}
    $0 <command> [options]

${YELLOW}コマンド:${NC}
    ${GREEN}list${NC}                         テンプレート一覧を表示
    ${GREEN}generate${NC}                     インタラクティブモードでドキュメント生成
    ${GREEN}generate <template> <output>${NC}  テンプレートを指定して生成

${YELLOW}例:${NC}
    $0 list
    $0 generate
    $0 generate feature/feature-spec.md docs/features/new-feature.md

${YELLOW}テンプレートの検索順序:${NC}
    1. $CUSTOM_TEMPLATES_DIR (ユーザー定義)
    2. $TEMPLATES_DIR (デフォルト)
EOF
}

# =============================================================================
# テンプレート検索
# =============================================================================

# テンプレートファイルを検索（カスタムテンプレート優先）
find_template() {
    local template_path="$1"

    # カスタムテンプレートを検索
    if [[ -f "$CUSTOM_TEMPLATES_DIR/$template_path" ]]; then
        echo "$CUSTOM_TEMPLATES_DIR/$template_path"
        return 0
    fi

    # デフォルトテンプレートを検索
    if [[ -f "$TEMPLATES_DIR/$template_path" ]]; then
        echo "$TEMPLATES_DIR/$template_path"
        return 0
    fi

    return 1
}

# =============================================================================
# テンプレート一覧表示
# =============================================================================

list_templates() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  利用可能なテンプレート${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    local count=0
    local seen=()

    # カスタムテンプレートを表示
    if [[ -d "$CUSTOM_TEMPLATES_DIR" ]]; then
        while IFS= read -r template; do
            [[ -f "$template" ]] || continue
            local category=$(dirname "$template" | sed "s|$CUSTOM_TEMPLATES_DIR/||")
            local filename=$(basename "$template")
            local relpath="${category}/${filename}"

            # 重複回避
            if [[ ! " ${seen[@]} " =~ " ${relpath} " ]]; then
                printf "  ${GREEN}[custom]${NC} ${CYAN}${relpath}${NC}\n"
                seen+=("$relpath")
                count=$((count + 1))
            fi
        done < <(find "$CUSTOM_TEMPLATES_DIR" -type f \( -name "*.md" -o -name "*.yaml" \) | sort)
    fi

    # デフォルトテンプレートを表示
    if [[ -d "$TEMPLATES_DIR" ]]; then
        while IFS= read -r template; do
            [[ -f "$template" ]] || continue
            [[ "$template" == *"README.md" ]] && continue

            local category=$(dirname "$template" | sed "s|$TEMPLATES_DIR/||")
            local filename=$(basename "$template")
            local relpath="${category}/${filename}"

            # 重複回避（カスタムテンプレートで上書きされている場合）
            if [[ ! " ${seen[@]} " =~ " ${relpath} " ]]; then
                printf "  ${BLUE}[default]${NC} ${CYAN}${relpath}${NC}\n"
                seen+=("$relpath")
                count=$((count + 1))
            fi
        done < <(find "$TEMPLATES_DIR" -type f \( -name "*.md" -o -name "*.yaml" \) | sort)
    fi

    echo ""
    printf "%b" "${GREEN}計 ${count}個のテンプレート${NC}\n"
    echo ""

    if [[ $count -eq 0 ]]; then
        printf "%b" "${YELLOW}テンプレートがありません${NC}\n"
    fi
}

# =============================================================================
# プレースホルダー抽出
# =============================================================================

extract_placeholders() {
    local template_path="$1"
    grep -oE '\{[A-Z_][A-Z0-9_]*\}' "$template_path" 2>/dev/null | sort -u | sed 's/[{}]//g'
}

# =============================================================================
# ドキュメント生成
# =============================================================================

generate_doc() {
    local template_path="$1"
    local output_path="$2"
    shift 2
    local -n variables=$1  # 名前参照連想配列（Bash 4.3+）

    # テンプレートを読み込み
    local content
    content=$(cat "$template_path")

    # プレースホルダーを置換
    for key in "${!variables[@]}"; do
        content="${content//\{$key\}/${variables[$key]}}"
    done

    # 現在日時を追加
    local current_date=$(date +"%Y-%m-%d")
    content="${content//\{CREATION_DATE\}/${current_date}}"

    # 出力ディレクトリを作成
    local output_dir=$(dirname "$output_path")
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
    fi

    # ファイルに書き込み
    echo "$content" > "$output_path"

    printf "%b" "${GREEN}✓ 生成完了: ${NC}${output_path}\n"
}

# =============================================================================
# インタラクティブモード
# =============================================================================

interactive_mode() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  ドキュメント生成ウィザード${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    # テンプレート一覧を表示
    list_templates

    echo ""
    printf "%b" "${YELLOW}テンプレートを選択してください:${NC}\n"
    read -rp "> " template_choice

    # テンプレートを検索
    local template_path
    template_path=$(find_template "$template_choice")

    if [[ -z "$template_path" ]]; then
        printf "%b" "${RED}エラー: テンプレートが見つかりません: $template_choice${NC}\n"
        return 1
    fi

    printf "%b" "${GREEN}選択されたテンプレート: ${NC}${template_path}\n"
    echo ""

    # 出力パスを入力
    printf "%b" "${YELLOW}出力パスを入力してください (${DOCS_DIR}からの相対パス):${NC}\n"
    read -rp "> " output_choice

    local output_path="${DOCS_DIR}/${output_choice}"
    printf "%b" "${GREEN}出力先: ${NC}${output_path}\n"
    echo ""

    # プレースホルダーを抽出
    local placeholders
    placeholders=$(extract_placeholders "$template_path")

    if [[ -z "$placeholders" ]]; then
        printf "%b" "${YELLOW}プレースホルダーがありません${NC}\n"
    else
        printf "%b" "${CYAN}以下のプレースホルダーに入力してください:${NC}\n"
        echo ""

        # 変数を入力
        declare -A variables
        while IFS= read -r placeholder; do
            [[ -z "$placeholder" ]] && continue

            # CREATION_DATE はスキップ（自動設定）
            if [[ "$placeholder" == "CREATION_DATE" ]]; then
                continue
            fi

            # デフォルト値を提示
            local default_value=""
            case "$placeholder" in
                AUTHOR)
                    default_value="${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo 'Your Name')}"
                    ;;
                FEATURE_NAME)
                    default_value="New Feature"
                    ;;
                TABLE_NAME)
                    default_value="table_name"
                    ;;
            esac

            local prompt="${placeholder}"
            [[ -n "$default_value" ]] && prompt="${placeholder} [デフォルト: ${default_value}]"

            read -rp "  ${prompt}: " value
            variables["$placeholder"]="${value:-$default_value}"
        done <<< "$placeholders"
        echo ""
    fi

    # ドキュメント生成
    printf "%b" "${BLUE}ドキュメントを生成中...${NC}\n"
    generate_doc "$template_path" "$output_path" variables

    # ファイルを開くか確認
    echo ""
    printf "%b" "${YELLOW}ファイルを開きますか？ (y/N):${NC} "
    read -r -n 1 response
    echo ""

    if [[ "$response" =~ ^[Yy]$ ]]; then
        # macOS vs Linux
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open "$output_path"
        elif command -v xdg-open &> /dev/null; then
            xdg-open "$output_path"
        else
            printf "%b" "${YELLOW}ファイルパス: ${output_path}${NC}\n"
        fi
    fi
}

# =============================================================================
# メイン処理
# =============================================================================

case "${1:-}" in
    list)
        list_templates
        ;;
    generate)
        if [[ -z "$2" ]]; then
            interactive_mode
        else
            # 直接指定モード
            local template_choice="$2"
            local output_choice="$3"

            if [[ -z "$output_choice" ]]; then
                printf "%b" "${RED}エラー: 出力パスを指定してください${NC}\n"
                echo "使用方法: $0 generate <template> <output>"
                exit 1
            fi

            # テンプレートを検索
            local template_path
            template_path=$(find_template "$template_choice")

            if [[ -z "$template_path" ]]; then
                printf "%b" "${RED}エラー: テンプレートが見つかりません: $template_choice${NC}\n"
                exit 1
            fi

            local output_path="${DOCS_DIR}/${output_choice}"

            # プレースホルダーを環境変数から取得（または空文字）
            declare -A variables
            local placeholders
            placeholders=$(extract_placeholders "$template_path")

            while IFS= read -r placeholder; do
                [[ -z "$placeholder" ]] && continue
                variables["$placeholder"]="${!placeholder:-}"
            done <<< "$placeholders"

            generate_doc "$template_path" "$output_path" variables
        fi
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        printf "%b" "${RED}エラー: 不明なコマンド '$1'${NC}\n"
        echo ""
        show_help
        exit 1
        ;;
esac
