# Y機能（タスク分解確認フロー）API仕様書

## バージョン情報

- **バージョン**: 1.0.0
- **最終更新**: 2025-02-07
- **対象ファイル**: `.claude/scripts/orchestrator.sh`

## 概要

Y機能は、Claude AIを活用したタスク分解とユーザー確認の対話フローを提供します。本ドキュメントは開発者向けの内部API仕様を記述します。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                    orch add コマンド                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              add_task_auto(task_desc)                       │
│  - タスク初期化                                              │
│  - AI/ルールベース分解ループ管理                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
                ▼                       ▼
┌───────────────────────┐   ┌──────────────────────────────┐
│  decompose_task_ai()  │   │  decompose_task_rules()      │
│  - Claude CLI 呼び出し│   │  - キーワードベース分解      │
└───────────┬───────────┘   └───────────┬──────────────────┘
            │                           │
            └───────────┬───────────────┘
                        │
                        ▼
            ┌───────────────────────────┐
            │  confirm_decomposition()  │
            │  - ユーザー確認フロー      │
            │  - Y/N/E/Q 選択肢         │
            └───────────┬───────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
            ▼                       ▼
    ┌───────────────┐       ┌────────────────┐
    │ 承認時の処理   │       │ 再試行ループ    │
    │ タスク登録     │       │ collect_feedback│
    └───────────────┘       └────────────────┘
```

## 核心関数仕様

### 1. `add_task_auto()`

**シグネチャ:**
```bash
add_task_auto <task_desc> [priority]
```

**引数:**
| パラメータ | 型 | 必須 | デフォルト | 説明 |
|-----------|------|------|-----------|------|
| `task_desc` | string | ✅ | - | タスクの説明 |
| `priority` | string | ❌ | `normal` | 優先度 (`critical`, `high`, `normal`, `low`) |

**戻り値:**
- `0` - 成功（タスク作成完了）
- `1` - 失敗（ユーザーキャンセル、またはエラー）

**環境変数:**
| 変数名 | 説明 | デフォルト値 |
|-------|------|-------------|
| `USE_AI` | AI分解を有効にする | `true` |
| `ORCH_AUTO_CONFIRM` | 自動承認モード | 未設定 |

**処理フロー:**

```bash
1. init_tasks() - タスクファイル初期化
2. ヘッダー表示

3. while [ attempt -le 3 && confirmed == false ]; do
   ├─ if [ attempt -eq 1 && USE_AI == true ]; then
   │  ├─ decompose_task_ai()
   │  └─ 失敗時は use_rules_fallback = true
   │
   ├─ if [ use_rules_fallback == true ]; then
   │  └─ ルールベース分解実行
   │
   ├─ 分解結果表示
   │
   ├─ confirm_decomposition()
   │  ├─ return 0 → confirmed = true (承認)
   │  ├─ return 1 → collect_feedback() → attempt++ (再分解)
   │  ├─ return 3 → edit_decomposition() → 確認再試行
   │  └─ return 4 → キャンセルして終了
   │
   └─ done

4. confirmed == true の場合:
   ├─ サブタスクを tasks.json に登録
   ├─ タスクIDの自動採番
   └─ 関連エージェントの自動起動
```

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 652-850

---

### 2. `decompose_task_ai()`

**シグネチャ:**
```bash
decompose_task_ai <task_desc> [feedback]
```

**引数:**
| パラメータ | 型 | 必須 | デフォルト | 説明 |
|-----------|------|------|-----------|------|
| `task_desc` | string | ✅ | - | 分解するタスクの説明 |
| `feedback` | string | ❌ | 空文字 | 前回のフィードバック |

**戻り値:**
- `0` - 成功（JSONをstdout出力）
- `1` - 失敗

**出力形式:**
```json
{
  "subtasks": [
    {
      "description": "サブタスクの説明",
      "agent": "frontend|backend|tests|docs",
      "rationale": "割り当て理由",
      "dependencies": [0, 1, ...]
    }
  ]
}
```

**前提条件:**
- `claude` コマンドがインストールされている
- `.claude/prompts/decompose_task.txt` が存在する

**処理フロー:**

```bash
1. コマンド存在確認
   └─ command -v claude || return 1

2. プロンプトファイル読み込み
   └─ .claude/prompts/decompose_task.txt

3. 入力プロンプト構築
   ├─ "タスク: {task_desc}"
   └─ "前回のフィードバック: {feedback}" (optional)

4. Claude CLI 実行
   └─ claude -p --system-prompt "$system_prompt" \
              --output-format text "$input_prompt" \
              </dev/null

5. JSON抽出
   ├─ マークダウンコードブロック除去
   └─ 先頭の{〜末尾の}を抽出

6. 検証
   ├─ jq empty でJSON形式チェック
   ├─ .error フィールドチェック
   └─ 有効ならJSONをstdoutに出力

7. ログ記録
   └─ orch_log "INFO" "AI分解成功: ${subtask_count} 個のサブタスク"
```

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 206-276

---

### 3. `confirm_decomposition()`

**シグネチャ:**
```bash
confirm_decomposition <decomposition_json> <attempt>
```

**引数:**
| パラメータ | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `decomposition_json` | string | ✅ | 分解結果のJSON |
| `attempt` | int | ✅ | 現在の試行回数 |

**戻り値:**
| 値 | 意味 |
|----|------|
| `0` | 承認（Y選択） |
| `1` | 再分解（N選択） |
| `2` | フォールバック（最大再試行回数超過） |
| `3` | 編集モード（E選択） |
| `4` | キャンセル（Q選択） |

**処理フロー:**

```bash
1. 分解結果表示
   ├─ 各サブタスクをフォーマット
   ├─ エージェント名に色付け
   └─ 理由・依存関係を表示

2. 確認プロンプト表示
   └─ "このプランで進めますか？"

3. 自動確認モードチェック
   └─ ORCH_AUTO_CONFIRM == yes → return 0

4. ユーザー入力読み取り
   ├─ read -r response
   └─ 先頭1文字を使用

5. case "$response" in
   ├─ [Yy]) return 0           # 承認
   ├─ [Nn]) if [ attempt -lt 3 ]
   │        then return 1      # 再分解
   │        else return 2      # フォールバック
   │        fi
   ├─ [Ee]) return 3           # 編集モード
   ├─ [Qq]) return 4           # キャンセル
   └─ *)     return 1          # 無効入力→再分解
```

**デバッグ機能:**
- stderr に `[DEBUG]` メッセージ出力
- 読み取り値、使用文字、case分岐をログ

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 318-433

---

### 4. `collect_feedback()`

**シグネチャ:**
```bash
collect_feedback <original_plan>
```

**引数:**
| パラメータ | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `original_plan` | string | ✅ | 元の分解プラン |

**戻り値:**
- `0` - フィードバック収集成功
- `1` - フィードバックなし（自動確認モード時）

**出力形式:**
```
action: <action_type>, <key>: <value>, ...
```

**アクションタイプ:**

| アクション | パラメータ | 例 |
|-----------|-----------|----|
| `add_subtask` | description | `action: add_subtask, description: パスワードリセット` |
| `remove_subtask` | index | `action: remove_subtask, index: 2` |
| `change_agent` | index, new_agent | `action: change_agent, index: 1, new_agent: frontend` |
| `modify_description` | index, new_description | `action: modify_description, index: 0, new_description: モダンなログインUI` |
| `freeform` | feedback | `action: freeform, feedback: セキュリティを強化して` |
| `retry_with_different_approach` | - | デフォルト |

**処理フロー:**

```bash
1. フィードバックメニュー表示
   └─ 5つのオプションを提示

2. 自動確認モードチェック
   └─ ORCH_AUTO_CONFIRM == yes → return 1

3. read -r choice

4. case "$choice" in
   ├─ 1) add_subtask 収集
   ├─ 2) remove_subtask 収集
   ├─ 3) change_agent 収集
   ├─ 4) modify_description 収集
   ├─ 5) freeform 収集
   └─ *) retry_with_different_approach

5. echo "$feedback"
```

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 436-501

---

### 5. `edit_decomposition()`

**シグネチャ:**
```bash
edit_decomposition <decomposition_json>
```

**引数:**
| パラメータ | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `decomposition_json` | string | ✅ | 編集前の分解JSON |

**戻り値:**
- `0` - 編集成功（編集後JSONをstdout出力）
- `1` - 編集失敗（無効なJSON）

**処理フロー:**

```bash
1. 現在のJSONを整形して表示
   └─ jq '.' でpretty print

2. 編集手順を案内

3. 入力読み取りループ
   ├─ while IFS= read -r line < /dev/tty; do
   ├─ if [[ -z "$line" ]]; then break; fi
   └─ edited_json += "$line\n"

4. JSON検証
   └─ validate_decomposition "$edited_json"

5. 有効なら出力、無効ならエラー
```

**入力ソース:**
- パイプ入力がない場合: `/dev/stdin`
- パイプ入力がある場合: `/dev/tty`

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 504-550

---

### 6. `validate_decomposition()`

**シグネチャ:**
```bash
validate_decomposition <json_string>
```

**引数:**
| パラメータ | 型 | 必須 | 説明 |
|-----------|------|------|------|
| `json_string` | string | ✅ | 検証するJSON文字列 |

**戻り値:**
- `valid` - 有効なJSON
- エラー文字列 - 無効な理由

**検証項目:**

1. **JSON形式チェック**
   ```bash
   echo "$json" | jq empty 2>/dev/null
   ```
   → 失敗時: `invalid_json`

2. **subtasksフィールドチェック**
   ```bash
   echo "$json" | jq 'has("subtasks")'
   ```
   → 失敗時: `missing_subtasks`

3. **サブタスク数チェック**
   ```bash
   echo "$json" | jq '.subtasks | length'
   ```
   → 0の場合: `no_subtasks`

4. **各サブタスクの必須フィールドチェック**
   ```bash
   echo "$json" | jq '.subtasks[] | has("description") and has("agent")'
   ```
   → 失敗時: `missing_required_fields`

5. **エージェント名チェック**
   ```bash
   echo "$json" | jq '.subtasks[].agent | IN("frontend","backend","tests","docs")'
   ```
   → 失敗時: `invalid_agent`

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 279-316

---

## データ構造

### タスク分解JSON

```json
{
  "subtasks": [
    {
      "description": "string (必須)",
      "agent": "frontend|backend|tests|docs (必須)",
      "rationale": "string (必須)",
      "dependencies": [number, ...] (オプション)
    }
  ]
}
```

### tasks.json スキーマ

```json
{
  "tasks": [
    {
      "id": number,
      "description": "string",
      "agent": "frontend|backend|tests|docs",
      "status": "pending|in_progress|completed|failed",
      "priority": "critical|high|normal|low",
      "dependencies": [number, ...],
      "progress": number (0-100),
      "created_at": "ISO8601 timestamp",
      "updated_at": "ISO8601 timestamp",
      "started_at": "ISO8601 timestamp (nullable)",
      "completed_at": "ISO8601 timestamp (nullable)"
    }
  ],
  "next_id": number
}
```

## プロンプト仕様

### AI分解プロンプト

**ファイル:** `.claude/prompts/decompose_task.txt`

**プレースホルダー:**
- `{TASK_DESCRIPTION}` - 実際のタスク説明で置換

**要件:**
- 3〜8個のサブタスクに分解
- 各サブタスクは1〜2時間で完了可能
- サブタスク間の依存関係を考慮
- 日本語で出力
- JSON形式のみ（markdownで囲まない）

**出力形式:**
```json
{
  "subtasks": [
    {
      "description": "サブタスクの説明",
      "agent": "エージェント名",
      "rationale": "なぜこのエージェントに割り当てたかの理由",
      "dependencies": []
    }
  ]
}
```

## 環境変数

| 変数名 | 説明 | デフォルト | 影響範囲 |
|-------|------|-----------|---------|
| `USE_AI` | AI分解を有効にする | `true` | `add_task_auto()` |
| `ORCH_AUTO_CONFIRM` | 自動承認モード | 未設定 | `confirm_decomposition()`, `collect_feedback()` |
| `CLAUDE_TIMEOUT` | Claude CLI タイムアウト（秒） | 未設定 | `decompose_task_ai()` |

## エラーハンドリング

### エラーコード一覧

| コード | 関数 | 説明 | 回復方法 |
|-------|------|------|---------|
| `1` | `decompose_task_ai()` | Claudeコマンド不在 | ルールベースにフォールバック |
| `1` | `decompose_task_ai()` | プロンプトファイル不在 | ルールベースにフォールバック |
| `1` | `decompose_task_ai()` | JSON出力なし | ルールベースにフォールバック |
| `1` | `validate_decomposition()` | 無効なJSON | エラー表示、再入力要求 |
| `1` | `edit_decomposition()` | 編集内容が無効 | エラー表示、再入力要求 |

### ログ出力

**ログ関数:** `orch_log()`

**ログレベル:**
- `INFO` - 通常処理
- `WARN` - 警告（フォールバックなど）
- `ERROR` - エラー

**ログファイル:**
- `.claude/logs/orchestrator-YYYY-MM-DD.log`

**ログ例:**
```
[2025-02-07 12:34:56] [INFO] AI分解開始: ユーザー認証機能の実装
[2025-02-07 12:35:02] [INFO] AI分解成功: 4 個のサブタスク
[2025-02-07 12:35:10] [INFO] タスク作成完了: 4個のタスクを作成しました
```

## ルールベース分解

### キーワードパターン

| キーワード | 分解後のサブタスク数 | 担当エージェント |
|-----------|---------------------|----------------|
| 認証/auth/login | 6 | Frontend, Backend×2, Tests×2, Docs |
| ユーザー登録/register/signup | 5 | Frontend, Backend×2, Tests, Docs |
| データベース/database/db | 5 | Backend×4, Docs |
| API/エンドポイント | 5 | Backend×3, Tests, Docs |
| UI/画面/コンポーネント | 5 | Frontend×4, Tests |
| テスト/test | 1 | Tests |
| ドキュメント/document/readme | 1 | Docs |

### 実装関数

```bash
decompose_task_rules() {
    local task_desc="$1"
    local detected_agent=$(detect_agent "$task_desc")
    local subtasks=()

    # キーワードマッチング
    # ...
    # パターンに応じたサブタスク追加

    printf '%s\n' "${subtasks[@]}"
}
```

**実装箇所:**
- ファイル: `.claude/scripts/orchestrator.sh`
- 行番号: 590-649

## 色設定

端末出力に使用されるANSIエスケープシーケンス:

| 変数 | コード | 色 |
|------|-------|---|
| `CYAN` | `\033[0;36m` | シアン |
| `GREEN` | `\033[0;32m` | 緑 |
| `YELLOW` | `\033[1;33m` | 黄色 |
| `RED` | `\033[0;31m` | 赤 |
| `BLUE` | `\033[0;34m` | 青 |
| `MAGENTA` | `\033[0;35m` | マゼンタ |
| `NC` | `\033[0;m` | リセット |

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `.claude/scripts/orchestrator.sh` | メイン実装ファイル |
| `.claude/prompts/decompose_task.txt` | AI分解プロンプト |
| `.claude/tasks.json` | タスクデータベース |
| `.claude/agents/*.json` | エージェント定義 |

## テスト仕様

### 単体テスト

**テスト対象:**
- `validate_decomposition()` - JSON検証ロジック
- `decompose_task_rules()` - キーワードマッチング

### 結合テスト

**テストシナリオ:**
1. 正常フロー: AI分解 → 承認 → タスク作成
2. 再試行フロー: AI分解 → 拒否 → フィードバック → 再分解 → 承認
3. 編集フロー: AI分解 → 編集 → 承認
4. フォールバックフロー: AI失敗 → ルールベース分解 → 承認
5. キャンセルフロー: AI分解 → キャンセル

## 今後の拡張案

1. **マルチリンガル対応** - プロンプトテンプレートの多言語化
2. **キャッシュ機能** - 同じタスクの分解結果をキャッシュ
3. **履歴管理** - 過去の分解結果の保存・参照
4. **カスタムプロンプト** - ユーザー定義の分解ルール
5. **フィードバック学習** - ユーザーフィードバックのパターン学習

## 関連ドキュメント

- [使用方法](./y-feature-usage.md) - ユーザー向け使用ガイド
- [システム仕様書](./specification.md) - 全体アーキテクチャ
- [承認機能仕様](./approval-test-specification.md) - 承認ワークフロー詳細
