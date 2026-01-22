# クイックスタートガイド

## 最小限の手順で起動する

### 1. Google認証キー配置 (オプション)

Vision APIを使う場合のみ必要:

```bash
# google-key.json をプロジェクトルートに配置
cp /path/to/your/google-key.json ./google-key.json
```

**注意:** google-key.json がなくても動作します（ダミーデータを使用）

### 2. 環境変数設定 (オプション)

kintone連携を使う場合のみ必要:

```bash
# .env.docker を編集
KINTONE_DOMAIN=your-domain.cybozu.com
KINTONE_API_TOKEN=your-api-token
```

### 3. システム起動

```bash
# 全サービスを起動
docker-compose up --build
```

起動完了まで約2-3分かかります。

### 4. 動作確認

別のターミナルで以下を実行:

```bash
# 1. Railsヘルスチェック
curl http://localhost:3000/health

# 2. Djangoヘルスチェック
curl http://localhost:8000/api/health/

# 3. PDFアップロードテスト
curl -X POST http://localhost:8000/api/parse/ \
  -F "pdf=@dummy.pdf"

# 4. 見積一覧取得
curl http://localhost:3000/estimates
```

### 5. 使ってみる

#### パターン1: ファイルパス指定で解析

```bash
# Railsコンテナ内のファイルパスを指定
curl -X POST http://localhost:3000/estimates/from_pdf \
  -H "Content-Type: application/json" \
  -d '{"pdf_path": "/rails/dummy.pdf"}'
```

#### パターン2: PDFファイルアップロード

```bash
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@/path/to/your/estimate.pdf"
```

#### パターン3: 最安比較

```bash
# wiper_blade の最安値を取得
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"
```

#### パターン4: kintoneにプッシュ

```bash
# 最安比較結果をkintoneに送信
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"
```

## 確認コマンド一覧

```bash
# コンテナ一覧
docker-compose ps

# ログ確認
docker-compose logs -f rails
docker-compose logs -f django
docker-compose logs -f mysql

# MySQLに接続
docker-compose exec mysql mysql -uroot -pvibepassword -e "SHOW DATABASES;"

# Railsコンソール
docker-compose exec rails bin/rails console

# Djangoシェル
docker-compose exec django python manage.py shell

# システム停止
docker-compose down

# データも削除して完全クリーン
docker-compose down -v
```

## トラブルシューティング

### エラー: "Cannot connect to Django service"

```bash
# Djangoが起動しているか確認
docker-compose ps django

# 起動していない場合は再起動
docker-compose restart django
```

### エラー: "Mysql2::Error: Access denied"

```bash
# MySQLのパスワードを確認
cat .env.docker | grep MYSQL_ROOT_PASSWORD

# docker-compose.yml と一致しているか確認
```

### エラー: "Vision API error"

google-key.json が無い、または無効な場合は**ダミーデータを使用します**。
Vision APIを使わなくてもシステムは動作します。

### ポートが既に使用されている

```bash
# 既存のサービスを確認
lsof -i :3000  # Rails
lsof -i :8000  # Django
lsof -i :3306  # MySQL

# docker-compose.yml のポートを変更
ports:
  - "3001:3000"  # 外部3001 -> 内部3000
```

## 開発Tips

### コンテナ内でコマンド実行

```bash
# Rails
docker-compose exec rails bin/rails routes
docker-compose exec rails bin/rails db:migrate

# Django
docker-compose exec django python manage.py makemigrations
docker-compose exec django python manage.py migrate
docker-compose exec django python manage.py createsuperuser
```

### ファイル編集後の反映

- **Rails**: コードを編集すると自動的に再読み込みされます
- **Django**: コードを編集すると自動的に再読み込みされます
- **Gemfile/requirements.txt変更時**: `docker-compose up --build` で再ビルド

### データベースリセット

```bash
# すべてのデータを削除
docker-compose down -v

# 再起動
docker-compose up --build
```

これでシステムが起動します！
