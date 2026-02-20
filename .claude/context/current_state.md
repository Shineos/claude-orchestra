# プロジェクト現在状態

最終更新: 2025-02-09

## 実装済み機能

### コア機能
- [x] Orchestratorによるタスク管理
- [x] 複数エージェントの連携（Frontend, Backend）
- [x] タスクの分解と依存関係管理
- [x] インタラクティブなタスク実行

### Phase 1: Architectエージェント（完了）
- [x] Architect専門エージェントの追加
- [x] タスクスキーマの拡張（contract, deliverables, verification_steps, definition_of_done）
- [x] 契約（Contract）システムのテンプレート作成
  - OpenAPI仕様書テンプレート（spec/api/TEMPLATE.yaml）
  - TypeScript型定義テンプレート（spec/types/TEMPLATE.d.ts）
  - データベーススキーマテンプレート（spec/db/TEMPLATE.prisma）

### Phase 2: Reviewerエージェント（完了）
- [x] Reviewer専門エージェントの追加
- [x] レビューワークフローの実装
- [x] Pre-Review自動チェック機能
- [x] 新しいステータスの追加（review_needed, rejected）
- [x] レビュー関連コマンドの追加
  - `orch review <task_id>` - タスクのレビュー
  - `orch approve <task_id>` - レビュー承認
  - `orch reject <task_id> <reason>` - レビュー却下
  - `orch review-create <task_id>` - レビュータスク作成

### Phase 3: コンテキスト・メモリ（実装中）
- [x] コンテキストディレクトリ構造の作成
- [x] ADRテンプレートの作成
- [x] context-manager.shスクリプトの作成
- [ ] コンテキスト読み込み機能のagent.shへの統合

## 技術スタック

### コアシステム
- **言語**: Bash 4.0+
- **設定**: JSON
- **バージョン管理**: Git

### エージェント定義
- **形式**: JSON
- **保存先**: `.claude/agents/`

### スクリプト
- **Orchestrator**: `.claude/scripts/orchestrator.sh`
- **Agent Runner**: `.claude/agent.sh`
- **Context Manager**: `.claude/scripts/context-manager.sh`
- **Pre-Review Check**: `.claude/scripts/pre-review-check.sh`

## 未解決の課題

### 優先度高
- [ ] Phase 4: 安全な並列実行機能
  - [ ] ロックファイル機構
  - [ ] Git Worktree対応
  - [ ] 依存関係の自動解決

### 優先度中
- [ ] Phase 5: ドキュメントテンプレート機能
- [ ] Phase 6: UI/UXダッシュボード

### 優先度低
- [ ] エージェントのパフォーマンス監視
- [ ] タスク実行の統計情報

## 次のマイルストーン

### v0.3.0 - 並列実行対応（予定）
- ロックファイルによる競合回避
- Git Worktreeによる分離された作業環境
- 依存関係に基づく自動並列実行

### v0.4.0 - ドキュメント自動生成（予定）
- テンプレート機能
- ADRからのドキュメント生成
- APIドキュメントの自動更新

### v0.5.0 - Webダッシュボード（予定）
- タスク管理UI
- エージェント状態の可視化
- リアルタイムログ表示

## プロジェクト設定

### エージェント定義
- `.claude/agents/orchestrator.json` - Orchestrator
- `.claude/agents/frontend.json` - Frontend Specialist
- `.claude/agents/backend.json` - Backend Specialist
- `.claude/agents/architect.json` - Architect Specialist
- `.claude/agents/reviewer.json` - Reviewer Specialist

### ディレクトリ構造
```
.claude/
├── agents/           # エージェント定義
├── context/          # プロジェクト記憶
│   ├── architectural_decisions/  # ADR
│   └── milestones/              # マイルストーン
├── scripts/          # ユーティリティスクリプト
└── tasks.json        # タスク管理データ
```

### 関連コマンド
```bash
# タスク管理
orch add <task> <agent>
orch start <task_id>
orch status

# レビュー
orch review <task_id>
orch approve <task_id>
orch reject <task_id> <reason>

# コンテキスト管理
./context-manager.sh adr <title>
./context-manager.sh list
./context-manager.sh update <summary>
```
