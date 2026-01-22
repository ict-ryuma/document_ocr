# 🚀 Document AI版 起動ガイド

## システム起動（3ステップ）

### ステップ1: 環境設定

```bash
# 1-1. プロジェクトディレクトリへ移動
cd /Users/ryumahoshi/Desktop/document_ocr

# 1-2. Google認証キー配置
cp /path/to/your/google-key.json ./google-key.json

# 1-3. 環境変数設定
vi .env.docker
```

**必須設定項目 (.env.docker):**
```bash
# Google Cloud Document AI
GCP_PROJECT_ID=your-project-id
DOCUMENT_AI_PROCESSOR_ID=6b217be4de9ac23f
DOCUMENT_AI_LOCATION=us

# kintone
KINTONE_DOMAIN=your-domain.cybozu.com
KINTONE_API_TOKEN=your-api-token
```

### ステップ2: システム起動

```bash
docker-compose up --build
```

**起動完了までの時間**: 約2-3分

**起動成功のサイン:**
```
vibe_rails    | => Booting Puma
vibe_django   | Booting worker with pid: X
vibe_mysql    | ready for connections
```

### ステップ3: 動作確認（別ターミナル）

```bash
# 3-1. Djangoヘルスチェック（Document AI確認）
curl http://localhost:8000/api/health/
# → "document_ai": "available" を確認

# 3-2. Railsヘルスチェック
curl http://localhost:3000/health

# 3-3. kintone接続確認
curl http://localhost:3000/kintone/health
# → "app_id": 316, "status": "healthy" を確認
```

---

## 完全動作テスト

### テスト1: PDF解析（Document AI）

```bash
# PDFをアップロードして解析
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@/path/to/your/estimate.pdf"

# 期待されるレスポンス:
{
  "estimate_id": 1,
  "vendor_name": "株式会社サンプル",
  "items_count": 5,
  "total_incl_tax": 16610,
  "items": [
    {
      "item_name_raw": "ワイパーブレード",
      "item_name_norm": "wiper_blade",
      "cost_type": "parts",
      "amount_excl_tax": 3800,
      "quantity": 1  ← Document AIが抽出
    },
    ...
  ]
}
```

### テスト2: 最安比較

```bash
# wiper_bladeの最安値を取得
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"

# 期待されるレスポンス:
{
  "single_vendor_best": {
    "vendor_name": "株式会社サンプル",
    "total": 6000,
    "estimate_id": 1
  },
  "split_theoretical_best": {
    "parts_min": 3800,
    "labor_min": 2200,
    "total": 6000
  },
  ...
}
```

### テスト3: kintoneプッシュ（サブテーブル含む）

```bash
# 最安比較結果をkintone App 316にプッシュ
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"

# 期待されるレスポンス:
{
  "success": true,
  "kintone_record_id": "123",
  "item_name": "wiper_blade",
  "details_count": 2,
  "subtable_name": "発注書"
}
```

**kintoneで確認:**
1. kintone App 316を開く
2. 新規レコードが作成されている
3. メインフィールド:
   - 品名: wiper_blade
   - 最安業者名: 株式会社サンプル
   - 最安単一合計: 6000
   - etc...
4. サブテーブル「発注書」:
   - 品名・加工方法: ワイパーブレード
   - 数量: 1
   - 単価: 3800
   - 課税区分: 課税
   - 正規化品名: wiper_blade
   - 費目: parts

---

## 新機能の違い

### ❌ 旧システム (Vision API)
- 単純なOCR（文字認識のみ）
- テーブル構造の認識が弱い
- 数量の抽出精度が低い

### ✅ 新システム (Document AI Form Parser)
- **Form Parser**: フォーム構造を理解
- **テーブル検出**: 表形式データを正確に抽出
- **数量抽出**: "x2", "2個" などを正確に認識
- **フィールド抽出**: "見積日"、"業者名"を自動抽出
- **精度向上**: 見積書・請求書に特化した学習モデル

---

## トラブルシューティング

### Q: Document AI エラーが出る

```bash
# エラー例: "Document AI client not initialized"

# 確認1: google-key.json が配置されているか
ls -la google-key.json

# 確認2: 環境変数が設定されているか
cat .env.docker | grep DOCUMENT_AI

# 確認3: Djangoコンテナ内で認証ファイルが見えるか
docker-compose exec django ls -la /app/credentials/google-key.json

# 解決策:
1. google-key.json を配置
2. .env.docker で GCP_PROJECT_ID を正しく設定
3. docker-compose restart django
```

### Q: kintone サブテーブルエラー

```bash
# エラー例: "Field not found: 発注書"

# 確認:
kintone App 316にサブテーブル「発注書」が作成されているか

# 必要なフィールド:
- 品名・加工方法 (SINGLE_LINE_TEXT)
- 数量 (NUMBER)
- 単価 (NUMBER)
- 課税区分 (DROP_DOWN: 課税/非課税/免税)
- 正規化品名 (SINGLE_LINE_TEXT)
- 費目 (DROP_DOWN: parts/labor)

# 解決策:
kintone_316_fields.json を参照してフィールドを作成
```

### Q: quantity カラムエラー

```bash
# エラー例: "Unknown column 'estimate_items.quantity'"

# 原因: マイグレーションが実行されていない

# 解決策:
docker-compose exec rails bin/rails db:migrate
docker-compose restart rails
```

---

## よく使うコマンド

```bash
# システム起動
docker-compose up --build

# バックグラウンド起動
docker-compose up -d

# ログ確認
docker-compose logs -f django
docker-compose logs -f rails

# システム停止
docker-compose down

# データも削除して完全クリーン
docker-compose down -v

# Railsマイグレーション実行
docker-compose exec rails bin/rails db:migrate

# Djangoマイグレーション実行
docker-compose exec django python manage.py migrate
```

---

## 参考ドキュメント

- **DOCUMENT_AI_UPGRADE.md**: アップグレード詳細
- **README.md**: システム全体マニュアル
- **kintone_316_fields.json**: フィールド定義
- **DEPLOYMENT_COMMANDS.md**: コマンド集

---

**準備完了！**

```bash
docker-compose up --build
```

これでDocument AI + kintone統合システムが起動します 🎉
