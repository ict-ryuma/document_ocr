# 起動コマンド集

## 初回セットアップ & 起動

```bash
# 1. プロジェクトディレクトリに移動
cd /Users/ryumahoshi/Desktop/document_ocr

# 2. google-key.json を配置 (オプション)
# 無くても動作します（ダミーデータ使用）
# cp /path/to/google-key.json ./google-key.json

# 3. 環境変数設定 (オプション)
# kintone連携する場合のみ編集
# vi .env.docker

# 4. システム起動
docker-compose up --build
```

## 起動確認コマンド (別ターミナルで実行)

```bash
# 1. ヘルスチェック - Rails
curl http://localhost:3000/health

# 期待される応答:
# {"status":"healthy","services":{...},"timestamp":"..."}

# 2. ヘルスチェック - Django
curl http://localhost:8000/api/health/

# 期待される応答:
# {"status":"healthy","service":"django-ocr","timestamp":"..."}

# 3. MySQL接続確認
docker-compose exec mysql mysql -uroot -pvibepassword -e "SHOW DATABASES;"

# 期待される出力:
# +--------------------+
# | Database           |
# +--------------------+
# | vibe_django        |
# | vibe_rails         |
# +--------------------+
```

## 動作テストコマンド

```bash
# テスト1: Djangoに直接PDFアップロード (ダミーPDF使用)
curl -X POST http://localhost:8000/api/parse/ \
  -F "pdf=@dummy.pdf"

# テスト2: Rails経由でPDFアップロード
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@dummy.pdf"

# テスト3: 見積一覧取得 (最初は空)
curl http://localhost:3000/estimates

# テスト4: 最安比較 (データがある場合)
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"

# テスト5: kintone連携確認 (設定済みの場合)
curl http://localhost:3000/kintone/health
```

## よく使うコマンド

### システム制御

```bash
# 起動 (フォアグラウンド)
docker-compose up

# 起動 (バックグラウンド)
docker-compose up -d

# 停止
docker-compose down

# 停止 & データ削除
docker-compose down -v

# 再起動
docker-compose restart

# 特定サービスのみ再起動
docker-compose restart rails
docker-compose restart django

# ログ確認 (リアルタイム)
docker-compose logs -f
docker-compose logs -f rails
docker-compose logs -f django
docker-compose logs -f mysql

# コンテナ状態確認
docker-compose ps
```

### データベース操作

```bash
# MySQLに接続
docker-compose exec mysql mysql -uroot -pvibepassword

# Rails DB確認
docker-compose exec mysql mysql -uroot -pvibepassword vibe_rails -e "SHOW TABLES;"

# Django DB確認
docker-compose exec mysql mysql -uroot -pvibepassword vibe_django -e "SHOW TABLES;"

# Rails マイグレーション実行
docker-compose exec rails bin/rails db:migrate

# Django マイグレーション実行
docker-compose exec django python manage.py migrate

# Railsコンソール
docker-compose exec rails bin/rails console

# Djangoシェル
docker-compose exec django python manage.py shell

# Django 管理ユーザー作成
docker-compose exec django python manage.py createsuperuser
```

### デバッグ & トラブルシューティング

```bash
# コンテナ内に入る
docker-compose exec rails bash
docker-compose exec django bash
docker-compose exec mysql bash

# Rails ルート確認
docker-compose exec rails bin/rails routes

# Django URL確認
docker-compose exec django python manage.py show_urls

# 環境変数確認
docker-compose exec rails env
docker-compose exec django env

# ディスク使用量確認
docker system df

# 不要なイメージ削除
docker system prune -a
```

### 開発時のリビルド

```bash
# Gemfile変更時 (Rails)
docker-compose build rails
docker-compose up rails

# requirements.txt変更時 (Django)
docker-compose build django
docker-compose up django

# 全サービス再ビルド
docker-compose up --build

# キャッシュ無しで完全再ビルド
docker-compose build --no-cache
docker-compose up
```

## サンプルデータ投入

```bash
# Railsコンソールでサンプル見積作成
docker-compose exec rails bin/rails console

# 以下をコンソール内で実行:
estimate = Estimate.create!(
  vendor_name: "サンプル自動車",
  estimate_date: Date.today,
  total_excl_tax: 15100,
  total_incl_tax: 16610
)

estimate.estimate_items.create!([
  {
    item_name_raw: "ワイパーブレード",
    item_name_norm: "wiper_blade",
    cost_type: "parts",
    amount_excl_tax: 3800
  },
  {
    item_name_raw: "ワイパー交換工賃",
    item_name_norm: "wiper_blade",
    cost_type: "labor",
    amount_excl_tax: 2200
  },
  {
    item_name_raw: "エンジンオイル 5W-30",
    item_name_norm: "engine_oil",
    cost_type: "parts",
    amount_excl_tax: 4800
  },
  {
    item_name_raw: "オイル交換工賃",
    item_name_norm: "engine_oil",
    cost_type: "labor",
    amount_excl_tax: 1500
  },
  {
    item_name_raw: "エアフィルター",
    item_name_norm: "air_filter",
    cost_type: "parts",
    amount_excl_tax: 2800
  }
])

# 確認
Estimate.count
EstimateItem.count
```

## パフォーマンスチェック

```bash
# コンテナリソース使用状況
docker stats

# 特定コンテナのリソース確認
docker stats vibe_rails vibe_django vibe_mysql

# ログサイズ確認
docker-compose exec rails du -sh log/
docker-compose exec django du -sh /app/media/
```

## 本番環境への移行準備

```bash
# 1. 環境変数を本番用に変更
vi .env.docker
# DEBUG=False
# RAILS_ENV=production
# SECRET_KEYを変更

# 2. 本番用ビルド
RAILS_ENV=production docker-compose up --build -d

# 3. アセットコンパイル (必要に応じて)
docker-compose exec rails bin/rails assets:precompile
docker-compose exec django python manage.py collectstatic

# 4. SSL証明書設定 (nginx等リバースプロキシ推奨)
```

これらのコマンドをコピペして実行できます！
