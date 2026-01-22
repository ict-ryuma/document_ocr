# ✅ Document AI アップグレード完了

## 実装完了内容

### 1. 🔄 Google Vision API → Document AI Form Parser

```
Before: Vision API (単純OCR)
After:  Document AI Form Parser (構造化解析)
        Processor ID: 6b217be4de9ac23f (Region: us)
```

**実装ファイル:**
- ✅ `django_ocr/requirements.txt` - google-cloud-documentai追加
- ✅ `django_ocr/utils/document_ai_parser.py` - **新規作成**（Form Parser統合）
- ✅ `django_ocr/parser/views.py` - Document AI使用に更新
- ✅ `django_ocr/config/settings.py` - Document AI設定追加

**解析精度向上:**
- テーブル構造の認識
- フォームフィールド抽出
- 数量の正確な抽出 (x2, 2個 等)
- 業者名・見積日の自動抽出

---

### 2. 📊 kintone App 316「発注書」サブテーブル完全対応

**サブテーブルマッピング:**
```
Document AI解析データ → kintone「発注書」サブテーブル

item_name_raw     → 品名・加工方法
quantity          → 数量 (Document AI抽出)
amount_excl_tax   → 単価
(固定値: "課税")  → 課税区分
item_name_norm    → 正規化品名 (wiper_blade等)
cost_type         → 費目 (parts/labor)
```

**実装ファイル:**
- ✅ `kintone_316_fields.json` - フィールド定義精密化
- ✅ `rails_app/app/services/kintone_service.rb` - **完全書き換え**
  - サブテーブル「発注書」対応
  - 課税区分「課税」固定設定
  - Document AIデータ自動マッピング

---

### 3. 🔢 Rails EstimateItem に quantity カラム追加

**データベース更新:**
- ✅ `rails_app/db/migrate/003_add_quantity_to_estimate_items.rb` - 新規作成
- ✅ `rails_app/app/controllers/estimates_controller.rb` - quantity保存対応
- ✅ `rails_app/app/models/estimate_item.rb` - デフォルト値設定

**データフロー:**
```
PDF → Document AI (数量抽出) → Rails EstimateItem.quantity → kintone「数量」
```

---

### 4. ⚙️ 環境変数設定

**追加された設定:**
```bash
# .env.docker
GCP_PROJECT_ID=your-project-id
DOCUMENT_AI_PROCESSOR_ID=6b217be4de9ac23f
DOCUMENT_AI_LOCATION=us
```

**更新ファイル:**
- ✅ `.env.docker` - Document AI設定追加
- ✅ `docker-compose.yml` - Django環境変数追加

---

## 📋 起動コマンド

### 1. 環境設定

```bash
# プロジェクトディレクトリへ移動
cd /Users/ryumahoshi/Desktop/document_ocr

# Google認証キー配置
cp /path/to/your/google-key.json ./google-key.json

# 環境変数設定
vi .env.docker
# → GCP_PROJECT_ID, DOCUMENT_AI_PROCESSOR_ID, KINTONE_DOMAIN, KINTONE_API_TOKEN を設定
```

### 2. システム起動

```bash
docker-compose up --build
```

**起動完了まで**: 約2-3分

### 3. 動作確認（別ターミナル）

```bash
# Djangoヘルスチェック（Document AI確認）
curl http://localhost:8000/api/health/
# → "document_ai": "available" を確認

# Railsヘルスチェック
curl http://localhost:3000/health

# kintone接続確認
curl http://localhost:3000/kintone/health
# → "app_id": 316, "status": "healthy" を確認
```

---

## 🧪 動作テストコマンド

### テスト1: PDF解析（Document AI）

```bash
curl -X POST http://localhost:3000/estimates/upload \
  -F "pdf=@/path/to/estimate.pdf"

# レスポンス例:
{
  "estimate_id": 1,
  "vendor_name": "株式会社サンプル",
  "items": [
    {
      "item_name_raw": "ワイパーブレード",
      "item_name_norm": "wiper_blade",
      "quantity": 1,  # ← Document AI抽出
      "amount_excl_tax": 3800
    }
  ]
}
```

### テスト2: 最安比較

```bash
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"
```

### テスト3: kintoneプッシュ（サブテーブル含む）

```bash
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"

# レスポンス例:
{
  "success": true,
  "kintone_record_id": "123",
  "subtable_name": "発注書",
  "details_count": 2
}
```

**kintone App 316で確認:**
- メインフィールド: 最安比較結果
- サブテーブル「発注書」:
  - 品名・加工方法: "ワイパーブレード"
  - 数量: 1
  - 単価: 3800
  - 課税区分: "課税"
  - 正規化品名: "wiper_blade"
  - 費目: "parts"

---

## 📂 変更ファイル一覧

### Django (10ファイル)
1. ✅ `django_ocr/requirements.txt`
2. ✅ `django_ocr/utils/document_ai_parser.py` ← **新規**
3. ✅ `django_ocr/parser/views.py`
4. ✅ `django_ocr/config/settings.py`

### Rails (4ファイル)
5. ✅ `rails_app/app/services/kintone_service.rb` ← **完全書き換え**
6. ✅ `rails_app/app/controllers/estimates_controller.rb`
7. ✅ `rails_app/db/migrate/003_add_quantity_to_estimate_items.rb` ← **新規**

### 設定 (3ファイル)
8. ✅ `kintone_316_fields.json`
9. ✅ `.env.docker`
10. ✅ `docker-compose.yml`

### ドキュメント (2ファイル)
11. ✅ `DOCUMENT_AI_UPGRADE.md` ← **新規**
12. ✅ `START_DOCUMENT_AI.md` ← **新規**

---

## ✨ 主な改善点

### Before (Vision API)
- ❌ 単純なOCR（文字認識のみ）
- ❌ テーブル構造の認識が弱い
- ❌ 数量抽出精度が低い
- ❌ kintoneサブテーブル未対応

### After (Document AI Form Parser)
- ✅ **Form Parser**でフォーム構造を理解
- ✅ **テーブル検出**で表形式データを正確に抽出
- ✅ **数量抽出**で "x2", "2個" を正確に認識
- ✅ **kintone App 316「発注書」サブテーブル完全対応**
- ✅ **課税区分「課税」固定設定**
- ✅ **Document AIデータを自動マッピング**

---

## 🎯 完成度チェックリスト

- [x] Document AI Form Parser統合
- [x] Processor ID 6b217be4de9ac23f 設定
- [x] PDF → 構造化データ抽出
- [x] テーブル・フォームフィールド検出
- [x] 品名・数量・単価の自動抽出
- [x] kintone App 316 メインフィールドマッピング
- [x] kintone サブテーブル「発注書」マッピング
- [x] 課税区分「課税」固定設定
- [x] 正規化品名と費目のサブテーブル追加
- [x] Rails EstimateItem に quantity カラム追加
- [x] 環境変数設定完備
- [x] ドキュメント更新

---

## 📚 ドキュメント

| ファイル | 内容 |
|---------|------|
| **START_DOCUMENT_AI.md** | 起動ガイド（このファイルを読めば起動できる） |
| **DOCUMENT_AI_UPGRADE.md** | アップグレード詳細（技術詳細） |
| **kintone_316_fields.json** | kintoneフィールド定義 |
| **README.md** | システム全体マニュアル |
| **DEPLOYMENT_COMMANDS.md** | コマンド集 |

---

## 🚀 次にやること

```bash
# 1. 環境設定
vi .env.docker
# → GCP_PROJECT_ID, DOCUMENT_AI_PROCESSOR_ID, KINTONE設定

# 2. Google認証キー配置
cp /path/to/google-key.json ./google-key.json

# 3. システム起動
docker-compose up --build

# 4. 動作確認（別ターミナル）
curl http://localhost:8000/api/health/
curl http://localhost:3000/kintone/health
```

---

**アップグレード完了日**: 2026年1月19日
**Document AI Processor**: 6b217be4de9ac23f (us)
**kintone App**: 316 (発注管理)
**ステータス**: ✅ 稼働準備完了

起動コマンド: `docker-compose up --build`
