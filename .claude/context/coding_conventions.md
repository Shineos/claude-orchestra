# Coding Conventions

このドキュメントでは、claude-orchestraプロジェクトのコーディング規約を定義します。

## Bashスクリプト規約

### ファイル構成

```bash
#!/bin/bash
# ==============================================================================
# スクリプトの説明
# ==============================================================================
#
# 詳細な説明...
#
# Usage:
#   script_name <command> [options]
#
# ==============================================================================

set -e  # エラーで終了

# 定数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ==============================================================================
# 定数・設定
# ==============================================================================

readonly CONFIG_FILE="$PROJECT_ROOT/config.json"
readonly MAX_RETRIES=3

# ==============================================================================
# ヘルパー関数
# ==============================================================================

show_help() {
    # ヘルプを表示
}

# ==============================================================================
# メイン処理
# ==============================================================================

main() {
    # メインロジック
}

main "$@"
```

### 命名規則

- **関数**: `snake_case`
  ```bash
  create_adr() { ... }
  update_task_status() { ... }
  ```

- **定数**: `UPPER_SNAKE_CASE`
  ```bash
  readonly MAX_RETRIES=3
  readonly CONTEXT_DIR="$SCRIPT_DIR/../context"
  ```

- **ローカル変数**: `snake_case`
  ```bash
  local task_id="$1"
  local status_value=""
  ```

- **グローバル変数**: `_prefix`（推奨しない）
  ```bash
  _cache_file="/tmp/cache"
  ```

### クォート規則

- **常に変数をダブルクォートで囲む**
  ```bash
  # Good
  local file="$SCRIPT_DIR/config.json"

  # Bad
  local file=$SCRIPT_DIR/config.json  # スペースを含むパスでエラー
  ```

- **文字列比較**
  ```bash
  if [[ "$status" == "completed" ]]; then
      # ...
  fi
  ```

### 条件分岐

```bash
# 文字列比較
if [[ -z "$string" ]]; then          # 空文字列チェック
    # ...
fi

if [[ "$value" == "expected" ]]; then
    # ...
fi

# ファイルチェック
if [[ -f "$file" ]]; then            # ファイル存在
    # ...
fi

if [[ -d "$dir" ]]; then             # ディレクトリ存在
    # ...
fi

# 論理演算子
if [[ "$condition1" ]] && [[ "$condition2" ]]; then
    # ...
fi
```

### ループ

```bash
# ファイルループ
for file in "$DIR"/*.md; do
    [[ -f "$file" ]] || continue
    # 処理
done

# 配列ループ
for item in "${array[@]}"; do
    echo "$item"
done

# カウンタループ
for ((i = 0; i < count; i++)); do
    echo "$i"
done
```

### エラーハンドリング

```bash
# set -e を使用（スクリプト開始時）
set -e

# エラーメッセージ付きで終了
if [[ -z "$required_param" ]]; then
    printf "%b" "${RED}エラー: 必須パラメータが不足しています${NC}\n" >&2
    exit 1
fi

# 関数内でエラーを処理
safe_operation() {
    if ! some_command; then
        return 1
    fi
}
```

### 色の出力

```bash
# 色の定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 使用例
printf "%b" "${GREEN}✓ 成功${NC}\n"
printf "%b" "${RED}✗ エラー${NC}\n" >&2
```

## JSON規約

### tasks.json

```json
{
  "tasks": [
    {
      "id": 1,
      "description": "タスク説明",
      "agent": "frontend",
      "status": "pending",
      "priority": "normal",
      "dependencies": [],
      "contract": null,
      "deliverables": [],
      "verification_steps": [],
      "definition_of_done": [],
      "created_at": "2025-01-01T00:00:00",
      "updated_at": "2025-01-01T00:00:00",
      "completed_at": null,
      "review_comments": null,
      "rejection_reason": null,
      "related_adr": []
    }
  ],
  "last_task_id": 1
}
```

### エージェント定義JSON

```json
{
  "name": "AgentName",
  "role": "specialist",
  "description": "エージェントの説明",
  "capabilities": ["capability1", "capability2"],
  "system_prompt": "システムプロンプト...",
  "interacts_with": ["agent1", "agent2"]
}
```

## ドキュメント規約

### Markdown

- **見出し**: `#` は文頭に1スペース
  ```markdown
  # 見出し1
  ## 見出し2
  ```

- **コードブロック**: 言語を指定
  ````markdown
  ```bash
  command_here
  ```
  ````

- **リスト**: 箇条書きはハイフン使用
  ```markdown
  - アイテム1
  - アイテム2
    - ネストされたアイテム
  ```

### ADR（Architecture Decision Record）

ADRは `.claude/context/architectural_decisions/TEMPLATE.md` のテンプレートに従います。

## Git規約

### コミットメッセージ

```
<type>: <subject>

<body>

<footer>
```

**type:**
- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメント
- `style`: フォーマット（コードの動作に影響しない）
- `refactor`: リファクタリング
- `test`: テスト追加・修正
- `chore`: ビルドプロセスやツールの変更

**例:**
```
feat: Architectエージェントの追加

- .claude/agents/architect.jsonを作成
- orchestrator.shにArchitect対応を追加
- タスクスキーマを拡張（contract, deliverables等）

Closes #123
```

## ファイル命名規約

| 種類 | 命名規則 | 例 |
|------|----------|-----|
| スクリプト | `kebab-case.sh` | `context-manager.sh` |
| JSON | `kebab-case.json` | `orchestrator.json` |
| Markdown | `kebab-case.md` | `coding-conventions.md` |
| ディレクトリ | `kebab-case` | `architectural_decisions` |
| ADR | `NNN-title.md` | `001-jwt-auth.md` |

## ベストプラクティス

1. **可読性優先**: 短く書くより、明確に書く
2. **早期リターン**: ネストを深くしない
3. **関数分割**: 1つの関数は1つの責任
4. **コメント**: 「何を」ではなく「なぜ」を書く
5. **エラーメッセージ**: 何が問題で、どうすればいいかを明示
