# Project Glossary

claude-orchestraプロジェクトで使用される専門用語と略語の定義。

## コア概念

### Orchestra / Orchestrator
プロジェクト名の由来。複数のAIエージェントを指揮者のように調整し、協調させて開発を行うシステム。

### Agent
AIエージェントのこと。特定の役割（Frontend, Backend, Architect, Reviewerなど）を持つ専門プログラム。

**種類:**
- **Orchestrator**: 全体の調整、タスク管理、分解を行うコアエージェント
- **Specialist**: 特定分野の専門家エージェント
  - Frontend: UI/UX実装
  - Backend: API・データベース実装
  - Architect: 設計・インターフェース定義
  - Reviewer: コードレビュー・品質保証

### Task
開発タスク。JSON形式で管理され、以下の属性を持つ：

- **id**: 一意識別子
- **description**: タスク説明
- **agent**: 担当エージェント
- **status**: 状態（pending, in_progress, review_needed, completed, rejected）
- **dependencies**: 依存するタスクIDのリスト
- **contract**: 契約ファイルパス（Architectが作成）

### Contract（契約）
Architectエージェントが作成する、タスクの仕様定義。

**構成要素:**
- **API仕様**: OpenAPI形式（YAML）
- **型定義**: TypeScript型定義
- **DBスキーマ**: Prisma形式

これらにより、FrontendとBackendの実装が統一されます。

## タスクステータス

| ステータス | 説明 |
|-----------|------|
| `pending` | 未着手。依存タスクの完了待ちの場合もある |
| `in_progress` | 実行中 |
| `review_needed` | 実装完了、レビュー待ち |
| `completed` | 完了 |
| `rejected` | レビューで却下、修正が必要 |

## 専門用語

### ADR (Architecture Decision Record)
アーキテクチャ決定記録。技術的な決定事項を記録する文書形式。

**目的:**
- 決定の背景を記録
- 後でなぜその決定をしたかを説明可能にする
- チームメンバー間で合意を形成

**構造:**
- ステータス（提案中/承認済み/却下/廃止）
- コンテキスト（なぜ決定が必要か）
- 決定内容
- 理由
- 代替案
- 影響

### DoD (Definition of Done)
完了定義。タスクが「完了」とみなされるための条件リスト。

**例:**
- [x] すべてのテストが通る
- [x] レビューで承認される
- [x] ドキュメントが更新される

### Pre-Review Check
レビュー前に実行する自動品質チェック。

**チェック項目:**
- Lint（コーディングスタイル）
- 型チェック（TypeScript等）
- テスト実行
- ビルドチェック

### Verification Step
検証ステップ。タスク完了時に実行する検証手順。

**例:**
```json
{
  "verification_steps": [
    "npm run lint",
    "npm run test",
    "npm run build"
  ]
}
```

## 並列実行関連

### Lock File
ロックファイル。並列実行時にリソースの競合を防ぐためのファイル。

**用途:**
- ファイルの同時書き込み防止
- タスクの重複実行防止
- リソースの排他制御

### Git Worktree
Gitのワークツリー機能。1つのリポジトリで複数の作業ディレクトリを持つ機能。

**利点:**
- 並列タスクを別ディレクトリで実行可能
- ブランチの切り替え不要
- クリーンな作業環境

### Dependency
依存関係。タスク間の前後関係。

**例:**
```json
{
  "id": 2,
  "dependencies": [1]  // タスク1が完了してから開始
}
```

## ディレクトリ・ファイル

### `.claude/`
プロジェクトの設定・スクリプトを格納するディレクトリ。

```
.claude/
├── agents/          # エージェント定義（JSON）
├── context/         # プロジェクト記憶
├── scripts/         # ユーティリティスクリプト
└── tasks.json       # タスク管理データ
```

### `spec/`
仕様書格納ディレクトリ。

```
spec/
├── api/             # API仕様書（OpenAPI）
├── types/           # TypeScript型定義
├── db/              # データベーススキーマ
└── *.md             # 仕様書ドキュメント
```

## コマンド

### `orch`
Orchestratorコマンド。タスク管理・操作を行う。

```bash
orch add <task> <agent>      # タスク追加
orch start <task_id>         # タスク開始
orch status                  # ステータス表示
orch review <task_id>        # レビュー実行
orch approve <task_id>       # 承認
orch reject <task_id> <reason>  # 却下
```

### `agent`
エージェント実行コマンド。

```bash
agent <agent_name> <task_id>
```

## 略語一覧

| 略語 | 正式名称 | 日本語 |
|------|----------|--------|
| ADR | Architecture Decision Record | アーキテクチャ決定記録 |
| API | Application Programming Interface | アプリケーションプログラミングインターフェース |
| CLI | Command Line Interface | コマンドラインインターフェース |
| DoD | Definition of Done | 完了定義 |
| JSON | JavaScript Object Notation | JSON形式 |
| UI | User Interface | ユーザーインターフェース |
| UX | User Experience | ユーザー体験 |
| YAML | YAML Ain't Markup Language | YAML形式 |

## 用語の日本語・英語対応

| 日本語 | 英語 | 備考 |
|--------|------|------|
| エージェント | Agent | |
| タスク | Task | |
| 契約 | Contract | |
| 依存関係 | Dependencies | |
| レビュー | Review | |
| 却下 | Reject | |
| 承認 | Approve | |
| 検証ステップ | Verification Steps | |
| 完了定義 | Definition of Done | |
| 前回チェック | Pre-Review Check | |
| ロックファイル | Lock File | |
| ワークツリー | Worktree | Git用語 |
