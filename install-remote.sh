#!/bin/bash
# Claude Orchestra リモートインストーラー
#
# 使用方法:
#   curl -fsSL https://raw.githubusercontent.com/shineos/claude-orchestra/main/install-remote.sh | bash -s -- /path/to/project
#
# オプション:
#   -v, --version VERSION   特定のバージョンをインストール (例: v1.0.0)
#   -h, --help              ヘルプを表示

set -e

# 色設定
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# GitHub リポジトリ設定
REPO_OWNER="shineos"
REPO_NAME="claude-orchestra"

# 引数解析
VERSION=""
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# gh CLIからトークン取得を試みる
if [[ -z "$GITHUB_TOKEN" ]] && command -v gh &> /dev/null; then
    GITHUB_TOKEN=$(gh auth token 2>/dev/null)
fi
TARGET_PROJECT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Claude Orchestra インストーラー"
            echo ""
            echo "使用方法:"
            echo "  curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/install-remote.sh | bash -s -- [オプション] /path/to/project"
            echo ""
            echo "オプション:"
            echo "  -v, --version VERSION   特定のバージョンをインストール (例: v1.0.0)"
            echo "  -h, --help              このヘルプを表示"
            exit 0
            ;;
        *)
            TARGET_PROJECT="$1"
            shift
            ;;
    esac
done

# ターゲットプロジェクトのチェック
if [[ -z "$TARGET_PROJECT" ]]; then
    TARGET_PROJECT="."
fi

if [[ ! -d "$TARGET_PROJECT" ]]; then
    printf "%b" "${RED}エラー: 指定されたパスが存在しません: $TARGET_PROJECT${NC}\n"
    exit 1
fi

printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "%b" "${CYAN}  Claude Orchestra リモートインストーラー${NC}\n"
printf "%b" "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""

# 最新バージョンを取得
if [[ -z "$VERSION" ]]; then
    printf "%b" "${CYAN}最新バージョンを確認中...${NC}\n"
    
    # GitHub API から最新リリースを取得
    LATEST_RELEASE_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    
    CURL_CMD="curl -fsSL"
    if [[ -n "$GITHUB_TOKEN" ]]; then
        CURL_CMD="curl -fsSL -H \"Authorization: token $GITHUB_TOKEN\""
    fi
    
    if command -v jq &> /dev/null; then
        # jq がある場合
        VERSION=$(eval "$CURL_CMD" "$LATEST_RELEASE_URL" | jq -r '.tag_name')
    else
        # jq がない場合は grep で抽出
        VERSION=$(eval "$CURL_CMD" "$LATEST_RELEASE_URL" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*: *"\([^"]*\)"/\1/')
    fi
    
    if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
        printf "%b" "${RED}エラー: 最新バージョンを取得できませんでした${NC}\n"
        exit 1
    fi
fi

printf "%b" "${GREEN}✓ バージョン: ${VERSION}${NC}\n"
echo ""

# ダウンロードURL
# 一時ディレクトリを作成
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# リリースをダウンロード
printf "%b" "${CYAN}ダウンロード中...${NC}\n"
if [[ -n "$GITHUB_TOKEN" ]]; then
    # Private Repo support
    # GitHub APIからリリースアセットIDを取得し、それを使ってダウンロード
    ASSET_ID=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$VERSION" | \
               grep -o '"id": [0-9]*' | head -n 1 | awk '{print $2}')

    if [[ -z "$ASSET_ID" ]]; then
        printf "%b" "${RED}エラー: リリースアセットIDを取得できませんでした。GITHUB_TOKENが正しいか、または指定されたバージョンが存在するか確認してください。${NC}\n"
        exit 1
    fi

    if ! curl -fsSL -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/octet-stream" \
         "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/assets/$ASSET_ID" \
         -o "$TMP_DIR/claude-orchestra.tar.gz"; then
        printf "%b" "${RED}エラー: プライベートリポジトリからのダウンロードに失敗しました。${NC}\n"
        printf "%b" "${YELLOW}ヒント: GITHUB_TOKENに適切な権限があるか確認してください。${NC}\n"
        exit 1
    fi
else
    # Public Repo support
    DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}/claude-orchestra.tar.gz"
    if ! curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/claude-orchestra.tar.gz"; then
        printf "%b" "${RED}エラー: リリースのダウンロードに失敗しました。${NC}\n"
        printf "%b" "${YELLOW}ヒント: プライベートリポジトリの場合は GITHUB_TOKEN を設定してください。${NC}\n"
        printf "%b" "${YELLOW}URL: ${DOWNLOAD_URL}${NC}\n"
        exit 1
    fi
fi

# 解凍
printf "%b" "${CYAN}解凍中...${NC}\n"
tar -xzf "$TMP_DIR/claude-orchestra.tar.gz" -C "$TMP_DIR"

# install.sh を実行
printf "%b" "${CYAN}インストール中...${NC}\n"
echo ""

# install.sh のパスを探す
INSTALL_SCRIPT=""
if [[ -f "$TMP_DIR/install.sh" ]]; then
    INSTALL_SCRIPT="$TMP_DIR/install.sh"
elif [[ -f "$TMP_DIR/claude-orchestra/install.sh" ]]; then
    INSTALL_SCRIPT="$TMP_DIR/claude-orchestra/install.sh"
else
    # 再帰的に探す
    INSTALL_SCRIPT=$(find "$TMP_DIR" -name "install.sh" -type f | head -1)
fi

if [[ -z "$INSTALL_SCRIPT" || ! -f "$INSTALL_SCRIPT" ]]; then
    printf "%b" "${RED}エラー: install.sh が見つかりません${NC}\n"
    exit 1
fi

chmod +x "$INSTALL_SCRIPT"
bash "$INSTALL_SCRIPT" "$TARGET_PROJECT"

echo ""
printf "%b" "${GREEN}✓ リモートインストールが完了しました${NC}\n"
