# Claude Orchestra Acceptance Tests

承認テスト（Acceptance Tests）スイート for Claude Orchestra マルチエージェントシステム。

## 概要

このテストスイートは、Claude OrchestraのCLIコマンドとエージェントのライフサイクル管理機能の動作を検証します。

## 前提条件

- **Bats**: Bash Automated Testing System
- **jq**: JSON処理コマンドラインツール
- **bash**: バージョン4.0以上

### インストール

```bash
# macOS
brew install bats-core jq

# Ubuntu/Debian
sudo apt install bats jq
```

## テスト構成

```
tests/
├── acceptance/
│   ├── orchestrator_commands.bats    # オーケストレータコマンドのテスト
│   └── agent_lifecycle.bats          # エージェント起動・管理のテスト
├── helpers/
│   └── bats_helper.bash              # 共通ヘルパー関数
├── fixtures/                         # テストフィクスチャ（将来拡張用）
└── run_tests.sh                      # テストランナー
```

## テストの実行

### すべてのテストを実行

```bash
./tests/run_tests.sh
```

### 詳細出力で実行

```bash
./tests/run_tests.sh --verbose
```

### 特定のテストパターンを実行

```bash
# オーケストレータ関連のテストのみ
./tests/run_tests.sh --filter orchestrator

# add コマンドのテストのみ
./tests/run_tests.sh --filter "add.*"
```

### 個別のテストファイルを実行

```bash
bats tests/acceptance/orchestrator_commands.bats
```

## テストカテゴリ

### Orchestrator Commands (`orchestrator_commands.bats`)

タスク管理のコマンドをテストします：

- **add**: タスク追加、エージェント自動割り当て、優先度、依存関係
- **status**: タスク一覧表示
- **start**: タスク開始
- **complete**: タスク完了
- **fail**: タスク失敗
- **next**: 実行可能タスクの表示
- **agents**: エージェント別ステータス表示

### Agent Lifecycle (`agent_lifecycle.bats`)

エージェントの起動と管理をテストします：

- **launch**: タスクに応じたエージェント一括起動
- **list/ps**: 実行中エージェント一覧
- **stop**: エージェント停止（個別/全員）
- **restart**: エージェント再起動
- **reset**: システム全体のリセット
- **monitor**: リアルタイム監視

## ヘルパー関数

`tests/helpers/bats_helper.bash` には以下のヘルパー関数が含まれています：

```bash
# タスク管理
add_task "description" [agent] [priority] [deps]
init_empty_tasks
task_count
get_task <id>
get_task_status <id>

# アサーション
assert_task_exists <id>
assert_task_status <id> <expected_status>
assert_agent_running <agent>
assert_agent_not_running <agent>

# フィクスチャ
create_fixture_task "description" [agent] [priority] [status]

# クリーンアップ
kill_running_agents
cleanup_test_worktrees
```

## テストの書き方

新しいテストファイルを作成する場合：

```bash
#!/usr/bin/env bats
load 'helpers/bats_helper'

setup() {
    setup
    init_empty_tasks
}

teardown() {
    teardown
}

@test "description of what is being tested" {
    # Arrange
    add_task "Test task" "backend"

    # Act
    run bash "$ORCHESTRATOR" start 1

    # Assert
    assert_success
    assert_output --partial "タスクを開始しました"
    assert_task_status 1 "in_progress"
}
```

## 環境変数

- `PROJECT_ROOT`: プロジェクトルートディレクトリ（自動検出）
- `BATS_VERBOSE`: `true` で詳細出力を有効化
- `CLAUDE_TIMEOUT`: エージェント実行タイムアウト（秒）

## CI/CD

GitHub Actionsワークフローが `.github/workflows/tests.yml` に含まれており、プッシュやプルリクエスト時に自動でテストが実行されます。

## トラブルシューティング

### テストが失敗する場合

1. **エージェントが残っている**: 手動で `orch stop all` を実行
2. **tasks.jsonが破損している**: バックアップから復元または削除
3. **権限の問題**: スクリプトに実行権限があるか確認

### デバッグモード

```bash
# 詳細ログを有効化
BATS_VERBOSE=true ./tests/run_tests.sh

# または特定のテストのみ
bats --verbose tests/acceptance/orchestrator_commands.bats
```

## 貢献

新しいテストを追加する際は：

1. 既存のテストパターンに従う
2. ヘルパー関数を再利用する
3. 適切なセットアップとティアダウンを実装する
4. テスト名は説明的にする

## ライセンス

MIT License - 親プロジェクトに準拠
