# APIフローシーケンス: {API_NAME}

## 概要
{API_DESCRIPTION}

## シーケンス図

```mermaid
sequenceDiagram
    autonumber

    participant U as User
    participant F as Frontend
    participant G as API Gateway
    participant A as Auth Service
    participant S as {SERVICE_NAME}
    participant D as Database

    Note over U,D: {SCENARIO_TITLE}

    U->>F: {USER_ACTION}
    F->>G: {HTTP_METHOD} {API_PATH}

    Note over G: 認証チェック
    G->>A: Validate Token
    A-->>G: Token Valid

    G->>S: Forward Request
    S->>D: {QUERY_TYPE}
    D-->>S: {RESULT}

    S-->>G: {RESPONSE_DATA}
    G-->>F: JSON Response
    F-->>U: Display Result
```

## エラーシナリオ

```mermaid
sequenceDiagram
    autonumber

    participant U as User
    participant F as Frontend
    participant G as API Gateway
    participant A as Auth Service
    participant S as {SERVICE_NAME}

    Note over U,S: {ERROR_SCENARIO_TITLE}

    U->>F: {USER_ACTION}
    F->>G: {HTTP_METHOD} {API_PATH}

    Note over G: 認証チェック
    G->>A: Validate Token
    A-->>G: Invalid Token

    G-->>F: 401 Unauthorized
    F-->>U: Redirect to Login
```

## API エンドポイント

### {ENDPOINT_NAME}

| 項目 | 値 |
|------|-----|
| メソッド | {HTTP_METHOD} |
| パス | {API_PATH} |
| 認証 | {AUTH_REQUIRED} |
| レート制限 | {RATE_LIMIT} |

### リクエスト

**ヘッダー:**
```http
{HEADER_NAME}: {HEADER_VALUE}
Content-Type: application/json
Authorization: Bearer {TOKEN}
```

**ボディ:**
```json
{
  "{PARAM_1}": "{VALUE_1}",
  "{PARAM_2}": "{VALUE_2}"
}
```

### レスポンス

**成功 (200 OK):**
```json
{
  "success": true,
  "data": {
    "{RESPONSE_FIELD_1}": "{RESPONSE_VALUE_1}",
    "{RESPONSE_FIELD_2}": "{RESPONSE_VALUE_2}"
  }
}
```

**エラー (4xx/5xx):**
```json
{
  "success": false,
  "error": {
    "code": "{ERROR_CODE}",
    "message": "{ERROR_MESSAGE}",
    "details": "{ERROR_DETAILS}"
  }
}
```

## 状態遷移図

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Request Received
    Processing --> Success: Valid Response
    Processing --> Error: Error Occurred
    Success --> Idle: Response Sent
    Error --> Idle: Error Response Sent
```

## タイミング要件

| フェーズ | 目標時間 | 最大許容時間 |
|---------|---------|--------------|
| {PHASE_1} | {TARGET_TIME_1} | {MAX_TIME_1} |
| {PHASE_2} | {TARGET_TIME_2} | {MAX_TIME_2} |

## 関連ドキュメント
- [API仕様書]({API_SPEC_PATH})
- [機能設計書]({FEATURE_SPEC_PATH})
- [テーブル設計書]({TABLE_DESIGN_PATH})

---
*作成日: {CREATION_DATE}*
*作成者: {AUTHOR}*
