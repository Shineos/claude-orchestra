# Context Directory

このディレクトリはプロジェクトの「記憶」を保持し、AIエージェント間でコンテキストを共有します。

## ディレクトリ構造

```
context/
├── README.md                    # このファイル
├── current_state.md             # プロジェクトの現在状態
├── coding_conventions.md        # コーディング規約
├── project_glossary.md          # プロジェクト用語集
├── architectural_decisions/     # ADR（アーキテクチャ決定記録）
│   └── TEMPLATE.md             # ADRテンプレート
└── milestones/                  # マイルストーン記録
```

## 各ファイルの用途

### current_state.md
- 実装済み機能の一覧
- 技術スタック
- 未解決の課題
- 次のマイルストーン

### coding_conventions.md
- コーディングスタイル
- 命名規則
- ファイル構成ルール
- ベストプラクティス

### project_glossary.md
- プロジェクト固有の用語定義
- 略語のリスト
- ドメイン知識

### architectural_decisions/
- 技術的な決定の記録
- 決定の理由と背景
- 代替案の検討
- 関連する他の決定事項

### milestones/
- リリース記録
- バージョンごとの変更点
- 完了したタスク

## 管理コマンド

```bash
# ADRを作成
./context-manager.sh adr "決定事項のタイトル"

# ADR一覧を表示
./context-manager.sh list

# ADR詳細を表示
./context-manager.sh show <adr_id>

# 現在状態を更新
./context-manager.sh update "変更内容のサマリー"

# マイルストーンを記録
./context-manager.sh milestone <version> "説明"
```

## エージェントによる使用

各エージェントはタスク実行前に、以下のコンテキストを自動的に読み込みます：

1. **関連するADR** - 関連するアーキテクチャ決定を理解
2. **コーディング規約** - プロジェクトのコーディングスタイルに従う
3. **現在状態** - 最新のプロジェクト状態を把握
4. **用語集** - ドメイン固有の用語を理解

これにより、一貫性のある品質の高いコードを生成できます。
