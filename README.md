# Document OCR System - 最強スタック統合版

Rails 7 + Django + MySQL による見積書OCR・比較・kintone連携システム

## システム構成

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Rails 7   │────▶│   Django     │────▶│   Vision    │
│  (API mode) │     │  (OCR/Parse) │     │     API     │
└──────┬──────┘     └──────────────┘     └─────────────┘
       │
       │            ┌──────────────┐
       ├───────────▶│    MySQL     │
       │            │  (2 DBs)     │
       │            └──────────────┘
       │
       │            ┌──────────────┐
       └───────────▶│   kintone    │
                    │  (app_id 316)│
                    └──────────────┘
```

### 技術スタック

- **Rails 7.x** (API モード)
  - 認証: Devise (予定)
  - DB: MySQL (`vibe_rails`)
  - 責務: 見積データ管理、最安比較ロジック、kintone連携

- **Django 5.x** (REST API)
  - OCR: Google Cloud Vision API
  - DB: MySQL (`vibe_django`)
  - 責務: PDF解析、品名正規化、解析履歴保存

- **MySQL 8.0**
  - 同一インスタンス内に2つのデータベース
  - `vibe_rails`: Railsのメインデータ
  - `vibe_django`: Django解析履歴

## ディレクトリ構成

```
document_ocr/
├── docker-compose.yml          # 全サービス統合起動
├── .env.docker                 # 環境変数設定
├── google-key.json            # Google Cloud認証キー (要配置)
├── kintone_316_fields.json    # kintoneフィールド定義
│
├── rails_app/                 # Rails APIアプリ
│   ├── Dockerfile.mysql
│   ├── Gemfile (mysql2追加済)
│   ├── app/
│   │   ├── models/
│   │   │   ├── estimate.rb
│   │   │   └── estimate_item.rb
│   │   ├── controllers/
│   │   │   ├── estimates_controller.rb
│   │   │   ├── recommendations_controller.rb
│   │   │   └── kintone_controller.rb
│   │   └── services/
│   │       ├── django_pdf_parser.rb    # Django連携
│   │       ├── kintone_service.rb      # kintone連携
│   │       └── estimate_price_query.rb
│   └── config/
│       └── routes.rb
│
├── django_ocr/               # Django OCRサービス
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── manage.py
│   ├── config/
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   ├── parser/
│   │   ├── models.py        # ParseHistory, ParsedItem
│   │   ├── views.py         # API endpoints
│   │   ├── urls.py
│   │   └── admin.py
│   └── utils/
│       ├── normalizer.py    # 品名正規化ロジック
│       └── vision_ocr.py    # Vision API連携
│
└── docker/
    └── mysql/
        └── init/
            └── 01-create-databases.sql
```

## セットアップ手順

### 1. 前提条件

- Docker & Docker Compose インストール済み
- Google Cloud アカウント (Vision API有効化)
- kintone アカウント (アプリID 316)

### 2. Google Cloud 認証キー配置

```bash
# google-key.json をプロジェクトルートに配置
cp /path/to/your/google-key.json ./google-key.json
```

### 3. 環境変数設定

```bash
# .env.docker を編集
vi .env.docker

# 必須設定項目:
# - KINTONE_DOMAIN: your-domain.cybozu.com
# - KINTONE_API_TOKEN: kintoneのAPIトークン
# - MYSQL_ROOT_PASSWORD: MySQLパスワード (デフォルト: vibepassword)
```

### 4. システム起動

```bash
# すべてのサービスをビルド & 起動
docker-compose up --build

# バックグラウンドで起動する場合
docker-compose up --build -d
```

起動順序:
1. MySQL (ヘルスチェック完了待ち)
2. Django (マイグレーション実行 → サーバー起動)
3. Rails (DB作成・マイグレーション → サーバー起動)

### 5. 起動確認

```bash
# Railsヘルスチェック
curl http://localhost:3000/health

# Djangoヘルスチェック
curl http://localhost:8000/api/health/

# kintone接続確認
curl http://localhost:3000/kintone/health
```

## API エンドポイント

### Rails API (port 3000)

#### 見積管理

```bash
# PDFアップロードして解析 (multipart)
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@/path/to/estimate.pdf" \
  -F "vendor_name=サンプル自動車"

# ファイルパス指定で解析
curl -X POST http://localhost:3000/estimates/from_pdf \
  -H "Content-Type: application/json" \
  -d '{"pdf_path": "/path/to/estimate.pdf"}'

# 見積一覧取得
curl http://localhost:3000/estimates

# 見積詳細取得
curl http://localhost:3000/estimates/1
```

#### 最安比較

```bash
# 品名別の最安値取得
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"

# レスポンス例:
{
  "single_vendor_best": {
    "vendor_name": "サンプル自動車",
    "total": 6000,
    "estimate_id": 1
  },
  "split_theoretical_best": {
    "parts_min": 3800,
    "labor_min": 2200,
    "total": 6000,
    "parts_vendor": "サンプル自動車",
    "labor_vendor": "サンプル自動車"
  },
  "all_estimates": [...]
}
```

#### kintone連携

```bash
# 最安比較結果をkintoneにプッシュ (サブテーブル含む)
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"

# レスポンス例:
{
  "success": true,
  "kintone_record_id": "123",
  "item_name": "wiper_blade",
  "details_count": 5
}
```

### Django API (port 8000)

```bash
# PDF解析 (multipart upload)
curl -X POST http://localhost:8000/api/parse/ \
  -F "pdf=@/path/to/estimate.pdf"

# 解析履歴取得
curl http://localhost:8000/api/history/
```

## データベース

### Rails DB (vibe_rails)

**estimates テーブル**
- id
- vendor_name (業者名)
- estimate_date (見積日)
- total_excl_tax (税抜合計)
- total_incl_tax (税込合計)
- created_at, updated_at

**estimate_items テーブル**
- id
- estimate_id (外部キー)
- item_name_raw (生の品名)
- item_name_norm (正規化済み品名: wiper_blade等)
- cost_type (parts/labor)
- amount_excl_tax (税抜金額)
- created_at, updated_at

### Django DB (vibe_django)

**parse_history テーブル**
- id
- pdf_filename
- vendor_name
- estimate_date
- total_excl_tax
- total_incl_tax
- raw_ocr_text (OCR生テキスト)
- parsed_json (解析結果JSON)
- created_at, updated_at

**parsed_items テーブル**
- id
- parse_history_id (外部キー)
- item_name_raw
- item_name_norm
- cost_type
- amount_excl_tax
- quantity
- created_at

## 品名正規化ルール

Django側の `utils/normalizer.py` で実装:

| 生データ例 | 正規化後 | 費目 |
|-----------|---------|------|
| ワイパーブレード | wiper_blade | parts |
| ワイパー交換工賃 | wiper_blade | labor |
| エンジンオイル 5W-30 | engine_oil | parts |
| オイル交換工賃 | engine_oil | labor |
| エアフィルター | air_filter | parts |
| ブレーキパッド | brake_pad | parts |
| タイヤ | tire | parts |

**費目判定ロジック:**
- 品名に「工賃」「labor」「取付」等が含まれる → `labor`
- それ以外 → `parts`

## kintone フィールドマッピング (app_id: 316)

詳細は `kintone_316_fields.json` 参照

### メインフィールド
- `item_name`: 正規化品名
- `best_vendor`: 最安業者名
- `best_single_total`: 単一業者最安合計
- `split_parts_min`: 分割最安部品代
- `split_labor_min`: 分割最安工賃
- `split_total`: 分割最安合計
- `comparison_date`: 比較実行日
- `notes`: 備考 (自動生成メッセージ)

### サブテーブル (order_details)
各見積明細を一覧化:
- `detail_vendor`: 業者名
- `detail_item_name`: 品名 (生)
- `detail_item_norm`: 正規化品名
- `detail_cost_type`: parts/labor
- `detail_amount`: 金額 (税抜)
- `detail_quantity`: 数量

## トラブルシューティング

### MySQLに接続できない

```bash
# MySQLコンテナのログ確認
docker-compose logs mysql

# MySQLコンテナに直接接続
docker-compose exec mysql mysql -uroot -pvibepassword

# データベース確認
SHOW DATABASES;
USE vibe_rails;
SHOW TABLES;
```

### Djangoが起動しない

```bash
# Djangoログ確認
docker-compose logs django

# Djangoコンテナに入る
docker-compose exec django bash

# マイグレーション手動実行
python manage.py migrate

# 管理ユーザー作成
python manage.py createsuperuser
```

### Railsが起動しない

```bash
# Railsログ確認
docker-compose logs rails

# Railsコンテナに入る
docker-compose exec rails bash

# DB作成・マイグレーション手動実行
bin/rails db:create db:migrate

# Gemインストール確認
bundle install
```

### Vision APIエラー

```bash
# google-key.json の配置確認
ls -la google-key.json

# Djangoコンテナ内での認証ファイル確認
docker-compose exec django ls -la /app/credentials/google-key.json

# 環境変数確認
docker-compose exec django env | grep GOOGLE
```

## 開発モード

個別サービスの開発時:

```bash
# Djangoのみ起動
docker-compose up django mysql

# Railsのみ起動
docker-compose up rails mysql

# ログをリアルタイム表示
docker-compose logs -f rails
docker-compose logs -f django
```

## 本番環境への移行

1. `.env.docker` の `DEBUG=False` に変更
2. `SECRET_KEY` を安全な値に変更
3. `ALLOWED_HOSTS` を本番ドメインに設定
4. MySQL パスワードを強固なものに変更
5. SSL/TLS 証明書の設定 (nginx等のリバースプロキシ経由)

## ライセンス

(プロジェクトのライセンスを記載)

## 作成者

Built with Rails 7, Django 5, MySQL 8, Google Vision API, and kintone
