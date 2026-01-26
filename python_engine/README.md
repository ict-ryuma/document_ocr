# Python PDF Parser Engine (Legacy/Stub)

> **Note**: このエンジンはMVP用のスタブです。  
> 本番環境では、Rails内の `OcrOrchestrationService` がDocument AI → GPT-4o Textのパイプラインを管理します。

## 現在のアーキテクチャ

```
PDF
 -> Document AI（事実・構造）
 -> GPT-4o Text（意味補完・例外吸収）
 -> Rails（検証・人確認）
```

## このエンジンの役割

- ローカル開発/テスト用のスタブ
- Railsサービスが利用できない場合のフォールバック

## Responsibilities

- Parse PDF and extract estimate data
- Normalize item names (e.g., ワイパー/wiper/ブレード → wiper_blade)
- Determine cost type (parts vs labor)
- Output JSON to stdout
- **NO database access**
- **NO kintone calls**
- **NO file writes**

## Usage

```bash
python3 main.py --pdf /path/to/estimate.pdf
```

## Output Format

### Success

```json
{
  "vendor_name": "Sample Auto Shop",
  "estimate_date": "2025-01-15",
  "total_excl_tax": 15100,
  "total_incl_tax": 16610,
  "items": [
    {
      "item_name_raw": "ワイパーブレード",
      "item_name_norm": "wiper_blade",
      "cost_type": "parts",
      "amount_excl_tax": 3800
    },
    {
      "item_name_raw": "ワイパー交換工賃",
      "item_name_norm": "wiper_blade",
      "cost_type": "labor",
      "amount_excl_tax": 2200
    }
  ]
}
```

### Error (file not found)

```json
{
  "error": "File not found: /path/to/missing.pdf"
}
```

## Normalization Rules

### Item Names

- ワイパー / wiper / ブレード / blade → `wiper_blade`
- エンジンオイル / engine oil / oil → `engine_oil`
- Other items: lowercase with underscores

### Cost Type

- Contains 工賃 / labor / installation / service → `labor`
- Otherwise → `parts`

## MVP Behavior

- If PDF file exists but is empty/dummy: returns sample data with 5 items
- If PDF file doesn't exist: returns error JSON and exits with code 0
- No actual PDF parsing in MVP - uses fixed sample data

## Dependencies

- Python 3.6+
- Standard library only (no external packages for MVP)

## Future Enhancements

- Actual PDF parsing with PyPDF2 or pdfplumber
- OCR support for scanned PDFs
- More sophisticated item name normalization
- Multi-vendor format support