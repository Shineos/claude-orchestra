# ドキュメントテンプレート

このディレクトリには、プロジェクトで使用するドキュメントテンプレートが含まれています。

## テンプレート一覧

### 機能設計 (feature/)
- `feature-spec.md` - 機能設計書テンプレート
- `user-story.md` - ユーザーストーリーテンプレート

### アーキテクチャ (architecture/)
- `architecture-diagram.md` - アーキテクチャ図テンプレート
- `component-diagram.md` - コンポーネント図テンプレート
- `deployment-diagram.md` - 配置図テンプレート

### シーケンス図 (sequence/)
- `api-flow.md` - APIフローシーケンス図テンプレート
- `user-flow.md` - ユーザーフローシーケンス図テンプレート

### データベース (database/)
- `table-design.md` - テーブル設計書テンプレート
- `er-diagram.md` - ER図テンプレート
- `migration-plan.md` - マイグレーション計画テンプレート

### API (api/)
- `openapi-template.yaml` - OpenAPI仕様書テンプレート
- `api-design.md` - API設計書テンプレート

### テスト (test/)
- `test-plan.md` - テスト計画テンプレート
- `test-case.md` - テストケーステンプレート

## 使用方法

```bash
# テンプレート一覧を表示
./template-manager.sh list

# インタラクティブモードでドキュメント生成
./template-manager.sh generate
```

## カスタムテンプレート

プロジェクト固有のテンプレートは `.claude/custom-templates/` に配置してください。
カスタムテンプレートはデフォルトテンプレートよりも優先されます。

## テンプレート変数

テンプレート内では `{VARIABLE_NAME}` 形式のプレースホルダーを使用します。
ドキュメント生成時に実際の値に置換されます。
