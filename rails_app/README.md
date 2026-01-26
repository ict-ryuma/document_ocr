# Document OCR Rails Application

自動車整備見積書のOCR処理・検証システム

## アーキテクチャ

```
PDF
 -> Document AI（事実・構造）
 -> GPT-4o Text（意味補完・例外吸収）
 -> Rails（検証・人確認）
```

### Stage 1: Document AI（事実・構造）
- Google Cloud Document AI を使用
- PDFからテーブル構造・フォームフィールドを抽出
- 文字認識（OCR）と構造解析

### Stage 2: GPT-4o Text（意味補完・例外吸収）
- Azure OpenAI GPT-4o を使用
- OCR誤認識の修正（例: 「ワイパ一」→「ワイパー」）
- 略称の正式名称への補完
- 例外パターンの吸収（セット価格、工賃込みなど）
- 金額の整合性検証

### Stage 3: Rails（検証・人確認）
- 抽出データの表示・編集UI
- ユーザーによる最終確認
- データベースへの保存
- kintoneへの連携

## 主要サービス

- `OcrOrchestrationService` - パイプライン全体のオーケストレーション
- `Ocr::DocumentAiAdapter` - Document AI連携
- `Ocr::GptTextAdapter` - GPT-4o Text意味補完
- `ProductNormalizerService` - 商品名正規化・コスト区分判定

## セットアップ

* Ruby version: 3.3+
* Rails version: 8.0+

### 環境変数

```bash
# Azure OpenAI
AZURE_OPENAI_API_KEY=xxx
AZURE_OPENAI_ENDPOINT=https://xxx.openai.azure.com
AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o

# Google Cloud Document AI
DOCUMENT_AI_PROJECT_ID=xxx
DOCUMENT_AI_LOCATION=us
DOCUMENT_AI_PROCESSOR_ID=xxx
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```

## テスト

```bash
bin/rails test
```
