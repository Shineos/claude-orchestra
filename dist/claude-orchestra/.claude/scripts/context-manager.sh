#!/bin/bash
# コンテキスト管理スクリプト
#
# プロジェクトの記憶（ADR、現在状態、規約）を管理します

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$SCRIPT_DIR/../context"
ADR_DIR="$CONTEXT_DIR/architectural_decisions"

# ==============================================================================
# ヘルプ
# ==============================================================================

show_help() {
    cat << EOF
${CYAN}Context Manager - プロジェクト記憶管理ツール${NC}

${YELLOW}使用方法:${NC}
    $0 <command> [options]

${YELLOW}コマンド:${NC}
    ${GREEN}adr <title>${NC}                  ADR（決定記録）を作成
    ${GREEN}update <summary>${NC}              現在状態を更新
    ${GREEN}milestone <version> <desc>${NC}    マイルストーンを記録
    ${GREEN}list${NC}                         ADR一覧を表示
    ${GREEN}show <adr_id>${NC}                ADR詳細を表示

${YELLOW}例:${NC}
    $0 adr "JWT認証の採用"
    $0 update "ログイン機能を実装"
    $0 milestone "v1.0.0" "初回リリース"
EOF
}

# ==============================================================================
# ADR関連関数
# ==============================================================================

# ADRを作成
create_adr() {
    local title="$1"

    if [[ -z "$title" ]]; then
        printf "%b" "${RED}エラー: タイトルを指定してください${NC}\n"
        echo "使用方法: $0 adr <title>"
        exit 1
    fi

    # 既存のADR数をカウント
    local adr_count=$(ls -1 "$ADR_DIR"/*.md 2>/dev/null | grep -v TEMPLATE | wc -l | xargs)
    local adr_number=$((adr_count + 1))
    local adr_id=$(printf "%03d" "$adr_number")
    local adr_file="$ADR_DIR/${adr_number}-$(echo "$title" | tr ' ' '-' | tr '[:upper:]' '[:lower:]').md"

    # テンプレートをコピー
    cp "$ADR_DIR/TEMPLATE.md" "$adr_file"

    # タイトルを置換
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/\[決定事項のタイトル\]/$title/" "$adr_file"
        sed -i '' "s/XXX/$adr_id/" "$adr_file"
        sed -i '' "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$adr_file"
    else
        # Linux
        sed -i "s/\[決定事項のタイトル\]/$title/" "$adr_file"
        sed -i "s/XXX/$adr_id/" "$adr_file"
        sed -i "s/YYYY-MM-DD/$(date +%Y-%m-%d)/" "$adr_file"
    fi

    printf "%b" "${GREEN}✓ ADRを作成しました${NC}\n"
    echo "ファイル: $adr_file"
    echo ""
    echo "次に、以下の項目を編集してください："
    echo "  - ステータス"
    echo "  - コンテキスト"
    echo "  - 決定内容"
    echo "  - 理由"
    echo "  - 代替案"
    echo "  - 影響"
}

# ADR一覧を表示
list_adr() {
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "%b" "${CYAN}  ADR一覧${NC}\n"
    printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""

    if [[ ! -d "$ADR_DIR" ]] || [[ -z "$(ls -A "$ADR_DIR" 2>/dev/null)" ]]; then
        printf "%b" "${YELLOW}ADRがありません${NC}\n"
        return
    fi

    for adr_file in "$ADR_DIR"/*.md; do
        [[ -f "$adr_file" ]] || continue
        [[ "$adr_file" == *TEMPLATE.md ]] && continue

        local basename=$(basename "$adr_file")
        local title=$(grep "^# " "$adr_file" | head -1 | sed 's/^# ADR-[0-9]*: //')
        local status=$(grep "^## ステータス" "$adr_file" | sed 's/^## ステータス //' | sed 's/\[.*\]//')

        # 色分け
        local status_color=""
        case "$status" in
            "承認済み") status_color="$GREEN" ;;
            "提案中") status_color="$YELLOW" ;;
            "却下") status_color="$RED" ;;
            "廃止") status_color="$CYAN" ;;
        esac

        printf "${CYAN}%s${NC} " "$basename"
        printf "| %b" "$status_color"
        printf "%-10s${NC} " "$status"
        printf "| %s\n" "$title"
    done

    echo ""
}

# ADR詳細を表示
show_adr() {
    local adr_id="$1"

    if [[ -z "$adr_id" ]]; then
        printf "%b" "${RED}エラー: ADR IDを指定してください${NC}\n"
        echo "使用方法: $0 show <adr_id>"
        echo "例: $0 show 001"
        exit 1
    fi

    # ファイルを探す
    local adr_file=""
    for f in "$ADR_DIR"/*.md; do
        if [[ "$(basename "$f" | cut -d'-' -f1)" == "$adr_id" ]]; then
            adr_file="$f"
            break
        fi
    done

    if [[ -z "$adr_file" ]]; then
        printf "%b" "${RED}エラー: ADR #$adr_id が見つかりません${NC}\n"
        exit 1
    fi

    cat "$adr_file"
}

# ==============================================================================
# 現在状態管理
# ==============================================================================

# 現在状態を更新
update_current_state() {
    local summary="$1"

    if [[ -z "$summary" ]]; then
        printf "%b" "${RED}エラー: サマリーを指定してください${NC}\n"
        echo "使用方法: $0 update <summary>"
        exit 1
    fi

    local state_file="$CONTEXT_DIR/current_state.md"

    # ファイルが存在しない場合は作成
    if [[ ! -f "$state_file" ]]; then
        cat > "$state_file" << 'EOF'
# プロジェクト現在状態

最終更新: YYYY-MM-DD

## 実装済み機能
- [x] 機能をここに記載

## 技術スタック
- **言語**:
- **フレームワーク**:
- **データベース**:

## 未解決の課題
- [ ] 課題をここに記載

## 次のマイルストーン
EOF
    fi

    # タイムスタンプを更新
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/最終更新: .*/最終更新: $(date +%Y-%m-%d)/" "$state_file"
    else
        sed -i "s/最終更新: .*/最終更新: $(date +%Y-%m-%d)/" "$state_file"
    fi

    # サマリーを追記
    echo "" >> "$state_file"
    echo "## 最新の変更 ($(date +%Y-%m-%d))" >> "$state_file"
    echo "$summary" >> "$state_file"

    printf "%b" "${GREEN}✓ 現在状態を更新しました${NC}\n"
}

# ==============================================================================
# マイルストーン管理
# ==============================================================================

# マイルストーンを記録
record_milestone() {
    local version="$1"
    local description="$2"

    if [[ -z "$version" ]] || [[ -z "$description" ]]; then
        printf "%b" "${RED}エラー: バージョンと説明を指定してください${NC}\n"
        echo "使用方法: $0 milestone <version> <description>"
        exit 1
    fi

    local milestone_file="$CONTEXT_DIR/milestones/$version.md"

    cat > "$milestone_file" << EOF
# マイルストーン: $version

## 日付
$(date +%Y-%m-%d)

## 概要
$description

## 完了したタスク
$(jq -r '.tasks[] | select(.status == "completed") | "- #\(.id): \(.description)"' "$SCRIPT_DIR/../tasks.json" 2>/dev/null || echo "なし")

## 主な変更
- (ここに主な変更を記載)

## 次のマイルストーン
- (次の目標を記載)
EOF

    printf "%b" "${GREEN}✓ マイルストーンを記録しました${NC}\n"
    echo "ファイル: $milestone_file"
}

# ==============================================================================
# メイン処理
# ==============================================================================

case "$1" in
    adr)
        create_adr "$2"
        ;;
    list)
        list_adr
        ;;
    show)
        show_adr "$2"
        ;;
    update)
        update_current_state "$2"
        ;;
    milestone)
        record_milestone "$2" "$3"
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
