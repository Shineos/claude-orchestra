# 承認機能要件定義書

## 概要

Claude Code マルチエージェントシステムにおける承認機能は、以下のシナリオで動作します。

### シナリオ1: タスク実行前の承認

エージェントがタスクを実行する前に、ユーザーの承認を必要とする場合があります。

- **トリガー**: 以下の操作は承認を必要とする
  - ファイルの作成・編集・削除
  - コマンドの実行（破壊的コマンドなど）
  - Git操作（commit, pushなど）

### シナリオ2: タスク完了の承認

タスク完了報告に対して、ユーザーが承認/却下を行うフローです。

- **フロー**:
  1. エージェントがタスク完了を報告
  2. ユーザーが結果を確認
  3. 承認または却下を選択
  4. 却下の場合、フィードバックを添えてエージェントに再実行指示

### シナリオ3: AI分解プランの承認

既存の機能ですが、より高度な承認フローが必要です。

- **現在**: タスク追加時に1回限りの承認
- **拡張案**: 承認履歴の保存、承認者情報の記録

## API エンドポイント仕様

承認機能を実現するためのAPIエンドポイント（コマンド）を定義します。

### 1. 承認リクエスト作成

```bash
orch request-approve <task_id> <operation_type> <details>
```

- **説明**: タスク実行前に承認をリクエスト
- **引数**:
  - `task_id`: タスクID
  - `operation_type`: 操作種別（file_write, command_exec, git_commit等）
  - `details`: 操作の詳細（JSON形式）
- **状態**: 承認待ち（pending_approval）

### 2. 承認待ち一覧表示

```bash
orch approval-queue
```

- **説明**: 承認待ちの操作一覧を表示
- **出力形式**:
  ```
  ID | Task | Operation | Details | Requested At
  1  | 5    | file_write| Write: src/app.ts | 2026-02-07 22:30
  2  | 5    | command   | Run: npm install  | 2026-02-07 22:31
  ```

### 3. 承認操作

```bash
orch approve <request_id> [--comment "comment"]
```

- **説明**: 承認リクエストを承認
- **引数**:
  - `request_id`: 承認リクエストID
  - `--comment`: オプションのコメント

### 4. 却下操作

```bash
orch reject <request_id> --reason "reason"
```

- **説明**: 承認リクエストを却下
- **引数**:
  - `request_id`: 承認リクエストID
  - `--reason`: 却下理由（必須）

### 5. 承認履歴表示

```bash
orch approval-history [task_id]
```

- **説明**: 承認履歴を表示
- **引数**:
  - `task_id`: オプションで特定タスクの履歴のみ表示

## データモデル

### tasks.json 拡張

```json
{
  "tasks": [
    {
      "id": 1,
      "description": "...",
      "status": "pending_approval",
      "approval_requests": [
        {
          "id": "req-001",
          "operation_type": "file_write",
          "details": {"file": "src/app.ts", "action": "write"},
          "requested_at": "2026-02-07T13:30:00Z",
          "requested_by": "agent:backend",
          "status": "pending",
          "response": null
        }
      ]
    }
  ],
  "approvals": [
    {
      "id": "req-001",
      "task_id": 1,
      "operation_type": "file_write",
      "details": {"file": "src/app.ts", "action": "write"},
      "requested_at": "2026-02-07T13:30:00Z",
      "requested_by": "agent:backend",
      "status": "approved",
      "response": {
        "action": "approved",
        "responded_at": "2026-02-07T13:31:00Z",
        "responded_by": "user",
        "comment": "Looks good"
      }
    }
  ]
}
```

## 承認ステータス

| ステータス | 説明 |
|----------|------|
| `pending` | 承認待ち |
| `approved` | 承認済み |
| `rejected` | 却下済み |
| `expired` | 期限切れ（デフォルト24時間） |

## テストシナリオ

### ユニットテスト項目

1. **承認リクエスト作成**
   - 正常系: リクエストが正しく作成される
   - 異常系: 不正な操作種別でエラー

2. **ステータス変更**
   - pending → approved
   - pending → rejected
   - approved → rejected（却下後の状態変更不可）

3. **タイムアウト処理**
   - 24時間経過でexpiredに変更

### 結合テスト項目

1. **承認リクエスト発行～承認フロー**
   - エージェントがリクエスト作成
   - ユーザーが承認
   - エージェントが操作実行

2. **却下フロー**
   - エージェントがリクエスト作成
   - ユーザーが却下
   - エージェントがフィードバックを受け取り再実行

### E2Eテスト項目

1. **承認待ち一覧表示**
   - 複数の承認待ちを表示
   - フィルタリング機能

2. **同時承認**
   - 複数のエージェントが同時にリクエスト

3. **期限切れ**
   - 期限切れのリクエストは自動的に却下

## 実装優先順位

1. **Phase 1**: 基本的な承認フロー
   - 承認リクエスト作成
   - 承認待ち一覧表示
   - 承認/却下操作

2. **Phase 2**: 拡張機能
   - 承認履歴
   - タイムアウト処理
   - バッチ承認

3. **Phase 3**: UI/UX改善
   - インタラクティブな承認画面
   - 通知機能
