#!/bin/bash
# Pre-Review 自動チェックスクリプト
#
# タスク完了前に自動チェックを実行します
# 使用方法: ./pre-review-check.sh <task_id> <agent>

set -e

TASK_ID="$1"
AGENT="$2"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "======================================================================"
echo "  Pre-Review 自動チェック"
echo "======================================================================"
echo "タスクID: $TASK_ID"
echo "エージェント: $AGENT"
echo ""

# チェック結果の集計
CHECKS_PASSED=0
CHECKS_FAILED=0

# ==============================================================================
# ヘルパー関数
# ==============================================================================

run_check() {
    local name="$1"
    local command="$2"

    echo "[$name] 実行中..."

    if eval "$command" > /dev/null 2>&1; then
        echo "✅ [$name] 成功"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        echo "❌ [$name] 失敗"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
        return 1
    fi
}

# ==============================================================================
# プロジェクトタイプ判定
# ==============================================================================

PROJECT_TYPE="unknown"
if [[ -f "package.json" ]]; then
    PROJECT_TYPE="node"
elif [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
    PROJECT_TYPE="python"
elif [[ -f "go.mod" ]]; then
    PROJECT_TYPE="go"
elif [[ -f "Cargo.toml" ]]; then
    PROJECT_TYPE="rust"
fi

# ==============================================================================
# チェック実行
# ==============================================================================

# TypeScript/JavaScript プロジェクト
if [[ "$PROJECT_TYPE" == "node" ]]; then
    # Lintチェック
    if command -v eslint &> /dev/null && [[ -f ".eslintrc.js" || -f ".eslintrc.json" || -f "eslint.config.js" ]]; then
        run_check "ESLint" "npm run lint -- --max-warnings=0"
    fi

    # 型チェック
    if command -v tsc &> /dev/null && [[ -f "tsconfig.json" ]]; then
        run_check "TypeScript型チェック" "npx tsc --noEmit"
    fi

    # テスト実行
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
        run_check "テスト" "npm test -- --passWithNoTests"
    fi

    # ビルドチェック
    if [[ -f "package.json" ]] && grep -q '"build"' package.json; then
        run_check "ビルド" "npm run build"
    fi

# Python プロジェクト
elif [[ "$PROJECT_TYPE" == "python" ]]; then
    # Lintチェック
    if command -v ruff &> /dev/null; then
        run_check "Ruff Lint" "ruff check ."
    elif command -v flake8 &> /dev/null; then
        run_check "Flake8" "flake8 ."
    fi

    # 型チェック
    if command -v mypy &> /dev/null; then
        run_check "Mypy" "mypy ."
    fi

    # テスト実行
    if command -v pytest &> /dev/null; then
        run_check "Pytest" "pytest"
    fi

# Go プロジェクト
elif [[ "$PROJECT_TYPE" == "go" ]]; then
    # Lintチェック
    if command -v golangci-lint &> /dev/null; then
        run_check "golangci-lint" "golangci-lint run"
    fi

    # テスト実行
    run_check "Go Test" "go test ./..."

# Rust プロジェクト
elif [[ "$PROJECT_TYPE" == "rust" ]]; then
    # Lintチェック
    run_check "Clippy" "cargo clippy -- -D warnings"

    # テスト実行
    run_check "Cargo Test" "cargo test"

    # ビルドチェック
    run_check "Cargo Build" "cargo build"
fi

# ==============================================================================
# 契約チェック
# ==============================================================================

CONTRACT_PATH=$(jq -r --argjson id "$TASK_ID" \
    '.tasks[] | select(.id == $id) | .contract // empty' \
    .claude/tasks.json 2>/dev/null)

if [[ -n "$CONTRACT_PATH" && -f "$CONTRACT_PATH" ]]; then
    echo "[契約チェック] $CONTRACT_PATH の検証..."
    if [[ "$CONTRACT_PATH" == *.yaml ]]; then
        if command -v yamllint &> /dev/null; then
            run_check "YAML構文" "yamllint '$CONTRACT_PATH'"
        fi
    fi
fi

# ==============================================================================
# 結果出力
# ==============================================================================

echo ""
echo "======================================================================"
echo "  チェック結果"
echo "======================================================================"
echo "✅ 成功: $CHECKS_PASSED"
echo "❌ 失敗: $CHECKS_FAILED"
echo ""

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo "🎉 すべてのチェックに合格しました"
    exit 0
else
    echo "⚠️  チェック失敗があります。修正してください。"
    exit 1
fi
