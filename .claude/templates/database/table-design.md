# テーブル設計書: {TABLE_NAME}

## 概要
{TABLE_DESCRIPTION}

## テーブル定義

### 物理名
`{TABLE_NAME}`

### 論理名
{TABLE_LOGICAL_NAME}

## カラム定義

| 物理名 | 論理名 | 型 | NULL | デフォルト | 説明 |
|--------|--------|-----|------|-----------|------|
| {COLUMN_1} | {LOGICAL_1} | {TYPE_1} | {NULL_1} | {DEFAULT_1} | {DESC_1} |
| {COLUMN_2} | {LOGICAL_2} | {TYPE_2} | {NULL_2} | {DEFAULT_2} | {DESC_2} |

## 制約

### 主キー
- `{PRIMARY_KEY_COLUMNS}`

### 外部キー
| カラム | 参照先テーブル | 参照先カラム | ON DELETE | ON UPDATE |
|--------|---------------|-------------|-----------|-----------|
| {FK_COLUMN} | {REF_TABLE} | {REF_COLUMN} | {ON_DELETE} | {ON_UPDATE} |

### ユニーク制約
- `{UNIQUE_COLUMNS}`

### インデックス
| インデックス名 | カラム | 種類 | 目的 |
|---------------|--------|------|------|
| {INDEX_NAME} | {INDEX_COLUMNS} | {INDEX_TYPE} | {PURPOSE} |

## ER図

```mermaid
erDiagram
    {TABLE_NAME} {
        {TYPE_1} {COLUMN_1} PK
        {TYPE_2} {COLUMN_2}
    }
    {RELATED_TABLE} {
        {TYPE_3} {COLUMN_3} PK
    }
    {TABLE_NAME} }o--|| {RELATED_TABLE} : "references"
```

## サンプルデータ

```sql
INSERT INTO {TABLE_NAME} ({COLUMNS}) VALUES
  ({SAMPLE_DATA_1}),
  ({SAMPLE_DATA_2});
```

## 関連ドキュメント
- [スキーマ定義]({SCHEMA_PATH})
- [マイグレーション]({MIGRATION_PATH})
- [機能設計書]({FEATURE_SPEC_PATH})

---
*作成日: {CREATION_DATE}*
*作成者: {AUTHOR}*
