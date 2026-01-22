# Document AI アップグレード完了報告書

## 実装完了内容

### ✅ 1. Google Cloud Document AI 統合

**変更内容:**
- Vision API → **Document AI Form Parser** に換装
- Processor ID: `6b217be4de9ac23f` (Region: us)
- より高精度な見積書・請求書解析を実現

**実装ファイル:**
- `django_ocr/requirements.txt`: google-cloud-documentai 追加
- `django_ocr/utils/document_ai_parser.py`: **新規作成** (Form Parser統合)
- `django_ocr/parser/views.py`: Document AI使用に更新
- `django_ocr/config/settings.py`: Document AI設定追加

**機能:**
- PDF → Form Parser → 構造化データ抽出
- テーブル検出・フォームフィールド抽出
- 品名、数量、単価の自動抽出
- 業者名、見積日の自動抽出

---

### ✅ 2. kintone App 316「発注書」サブテーブル完全対応

**kintone フィールドマッピング (精密実装):**

#### メインフィールド
| Rails | kintone フィールドコード | 用途 |
|-------|-------------------------|------|
| item_name | `item_name` | 正規化品名 |
| best_vendor | `best_vendor` | 最安業者名 |
| best_single_total | `best_single_total` | 単一業者最安合計 |
| split_parts_min | `split_parts_min` | 分割最安部品代 |
| split_labor_min | `split_labor_min` | 分割最安工賃 |
| split_total | `split_total` | 分割最安合計 |
| comparison_date | `comparison_date` | 比較実行日 |
| notes | `notes` | 備考（自動生成） |

#### サブテーブル「発注書」
| Document AI解析データ | kintone フィールドコード | 説明 |
|----------------------|-------------------------|------|
| item_name_raw | `品名・加工方法` | 解析した品名 |
| quantity | `数量` | Document AI抽出数量 |
| amount_excl_tax | `単価` | 単価（税抜） |
| (固定値) | `課税区分` | 「課税」固定 |
| item_name_norm | `正規化品名` | wiper_blade等 |
| cost_type | `費目` | parts/labor |

**実装ファイル:**
- `kintone_316_fields.json`: フィールド定義を精密化
- `rails_app/app/services/kintone_service.rb`: **完全書き換え**
  - `build_subtable_rows`: Document AIデータをサブテーブルにマッピング
  - 課税区分を「課税」固定で設定
  - 正規化品名と費目を自動追加

---

### ✅ 3. Rails EstimateItem に quantity カラム追加

**マイグレーション:**
- `rails_app/db/migrate/003_add_quantity_to_estimate_items.rb`: 新規作成
- `quantity` カラム追加 (デフォルト: 1)

**更新ファイル:**
- `rails_app/app/controllers/estimates_controller.rb`: quantityをDocument AIから取得
- `rails_app/app/models/estimate_item.rb`: quantityデフォルト値設定

---

### ✅ 4. 環境変数設定

**追加された環境変数:**
```bash
# Google Cloud Document AI
GCP_PROJECT_ID=your-project-id
DOCUMENT_AI_PROCESSOR_ID=6b217be4de9ac23f
DOCUMENT_AI_LOCATION=us
```

**設定ファイル:**
- `.env.docker`: Document AI設定追加
- `docker-compose.yml`: Django環境変数に追加
- `django_ocr/config/settings.py`: Document AI設定読み込み

---

## データフロー

```
┌─────────────────────────────────────────────────────────────┐
│                     完全統合フロー                           │
└─────────────────────────────────────────────────────────────┘

1. PDF アップロード (Rails API)
   ↓
2. Django Document AI 解析
   - Form Parser実行 (Processor: 6b217be4de9ac23f)
   - テーブル抽出
   - フォームフィールド抽出
   - 品名、数量、単価を構造化
   ↓
3. Django 正規化処理
   - 品名正規化 (wiper_blade等)
   - 費目判定 (parts/labor)
   - 数量抽出
   ↓
4. Rails DB保存
   - Estimate: 見積マスタ
   - EstimateItem: 明細（数量含む）
   ↓
5. 最安比較ロジック
   - 単一業者最安
   - 分割最安（部品+工賃）
   ↓
6. kintone App 316 プッシュ
   - メインフィールド: 最安比較結果
   - サブテーブル「発注書」: Document AI解析明細
     ├─ 品名・加工方法
     ├─ 数量
     ├─ 単価
     ├─ 課税区分（課税）
     ├─ 正規化品名
     └─ 費目
```

---

## 起動方法

### 前提条件
1. **Google Cloud設定**
   - Document AI API有効化
   - Processor作成 (Form Parser, ID: 6b217be4de9ac23f)
   - google-key.json 取得

2. **kintone設定**
   - App 316「発注管理」作成
   - サブテーブル「発注書」作成
   - APIトークン発行

### セットアップ

```bash
# 1. プロジェクトディレクトリへ移動
cd /Users/ryumahoshi/Desktop/document_ocr

# 2. Google認証キー配置
cp /path/to/your/google-key.json ./google-key.json

# 3. 環境変数設定
vi .env.docker

# 以下を設定:
# GCP_PROJECT_ID=your-project-id
# DOCUMENT_AI_PROCESSOR_ID=6b217be4de9ac23f
# DOCUMENT_AI_LOCATION=us
# KINTONE_DOMAIN=your-domain.cybozu.com
# KINTONE_API_TOKEN=your-api-token

# 4. システム起動
docker-compose up --build
```

### 起動確認

```bash
# 別ターミナルで実行

# 1. Djangoヘルスチェック（Document AI確認）
curl http://localhost:8000/api/health/
# → "document_ai": "available" を確認

# 2. Railsヘルスチェック
curl http://localhost:3000/health

# 3. kintone接続確認
curl http://localhost:3000/kintone/health
# → "status": "healthy", "app_id": 316 を確認
```

---

## 動作テスト

### 1. PDF解析テスト（Document AI使用）

```bash
# PDFをアップロードして解析
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@/path/to/estimate.pdf"

# レスポンス例:
{
  "estimate_id": 1,
  "vendor_name": "サンプル自動車",
  "items_count": 5,
  "total_incl_tax": 16610,
  "items": [
    {
      "item_name_raw": "ワイパーブレード",
      "item_name_norm": "wiper_blade",
      "cost_type": "parts",
      "amount_excl_tax": 3800,
      "quantity": 1
    },
    ...
  ]
}
```

### 2. 最安比較テスト

```bash
# wiper_blade の最安値を取得
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
    "total": 6000
  },
  ...
}
```

### 3. kintone プッシュテスト（サブテーブル含む）

```bash
# 最安比較結果をkintone App 316にプッシュ
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"

# レスポンス例:
{
  "success": true,
  "kintone_record_id": "123",
  "item_name": "wiper_blade",
  "details_count": 2,
  "subtable_name": "発注書"
}
```

**kintoneで確認すべき内容:**
- メインフィールド: 最安比較結果が入っている
- サブテーブル「発注書」:
  - 品名・加工方法: "ワイパーブレード" 等
  - 数量: 1
  - 単価: 3800
  - 課税区分: "課税"
  - 正規化品名: "wiper_blade"
  - 費目: "parts"

---

## トラブルシューティング

### Document AI エラー

```bash
# エラー: "Document AI client not initialized"
→ google-key.json が配置されていない、または環境変数が正しくない

# 確認コマンド:
docker-compose exec django ls -la /app/credentials/google-key.json
docker-compose exec django env | grep DOCUMENT_AI

# 解決:
1. google-key.json を配置
2. .env.docker でGCP_PROJECT_IDを設定
3. docker-compose restart django
```

### kintone サブテーブルエラー

```bash
# エラー: "Field not found: 発注書"
→ kintone App 316にサブテーブル「発注書」が作成されていない

# 確認:
- kintone App 316を開く
- フィールド設定で「発注書」サブテーブルが存在するか確認
- サブテーブル内に以下のフィールドがあるか:
  - 品名・加工方法
  - 数量
  - 単価
  - 課税区分
  - 正規化品名
  - 費目

# 参考: kintone_316_fields.json を見てフィールド作成
```

### quantity カラムエラー

```bash
# エラー: "Unknown column 'quantity'"
→ マイグレーションが実行されていない

# 解決:
docker-compose exec rails bin/rails db:migrate
docker-compose restart rails
```

---

## 変更ファイル一覧

### Django (Document AI対応)
- ✅ `django_ocr/requirements.txt` - google-cloud-documentai追加
- ✅ `django_ocr/utils/document_ai_parser.py` - **新規作成**
- ✅ `django_ocr/parser/views.py` - Document AI使用
- ✅ `django_ocr/config/settings.py` - Document AI設定

### Rails (kintone精密化)
- ✅ `rails_app/app/services/kintone_service.rb` - **完全書き換え**
- ✅ `rails_app/app/controllers/estimates_controller.rb` - quantity対応
- ✅ `rails_app/db/migrate/003_add_quantity_to_estimate_items.rb` - **新規**

### 設定
- ✅ `kintone_316_fields.json` - サブテーブル定義精密化
- ✅ `.env.docker` - Document AI環境変数追加
- ✅ `docker-compose.yml` - Django環境変数追加

---

## 完成度チェックリスト

- [x] Document AI Form Parser統合
- [x] PDF → Document AI → 構造化データ
- [x] 品名、数量、単価の自動抽出
- [x] kintone App 316 メインフィールドマッピング
- [x] kintone サブテーブル「発注書」マッピング
- [x] 課税区分「課税」固定設定
- [x] 正規化品名と費目のサブテーブル追加
- [x] Rails EstimateItem に quantity追加
- [x] 環境変数設定完備
- [x] ドキュメント更新

---

## 次のステップ（オプション）

1. **Document AI Processor カスタマイズ**
   - 独自のカスタムプロセッサ作成
   - 業界特化型の解析ロジック

2. **kintone Webhook連携**
   - kintone側からPDF再解析リクエスト
   - ステータス更新の自動化

3. **バッチ処理**
   - 複数PDFの一括解析
   - スケジュールバッチ実行

---

**アップグレード完了日**: 2026年1月19日
**Document AI Processor ID**: 6b217be4de9ac23f
**kintone App ID**: 316
**ステータス**: ✅ 稼働準備完了
