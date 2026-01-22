# Python Engine for PDF Invoice Parsing

## Overview

This is a stateless Python engine that parses PDF invoices and outputs structured JSON data. It is designed to be called from Rails applications.

## Features

- PDF text extraction via OCR (stub implementation)
- Invoice data parsing (vendor, date, totals, line items)
- Item name normalization (e.g., wiper-related terms → `wiper_blade`)
- Cost type classification (`parts` vs `labor`)
- JSON output to stdout

## Installation

```bash
pip install -r requirements.txt
```

## Usage

```bash
python python_engine/main.py --pdf dummy.pdf
```

### Output Format

```json
{
  "vendor_name": "株式会社サンプル自動車",
  "estimate_date": "2024-01-15",
  "total_excl_tax": 31700,
  "total_incl_tax": 34870,
  "items": [
    {
      "item_name_raw": "ワイパーブレード交換",
      "item_name_norm": "wiper_blade",
      "cost_type": "parts",
      "amount_excl_tax": 3500
    },
    {
      "item_name_raw": "オイル交換工賃",
      "item_name_norm": "オイル交換工賃",
      "cost_type": "labor",
      "amount_excl_tax": 2000
    }
  ]
}
```

## Architecture

### Modules

- **main.py**: Entry point, orchestrates the parsing pipeline
- **ocr_stub.py**: OCR stub that returns mock text data
- **parser.py**: Extracts structured data from raw text
- **normalizer.py**: Normalizes item names and classifies cost types

### Design Principles

- **Stateless**: No database, file system, or external service dependencies
- **Stdout output**: Results written to stdout as JSON
- **Modular**: Separated concerns for easy testing and extension

## Normalization Rules

### Item Names

- `ワイパー`, `wiper`, `ブレード` → `wiper_blade`
- Other items remain unchanged

### Cost Types

- Contains `工賃` → `labor`
- Otherwise → `parts`

## Testing

Create a dummy PDF file and run:

```bash
touch dummy.pdf
python python_engine/main.py --pdf dummy.pdf
```

## Future Enhancements

- Real OCR integration (Tesseract, Google Vision API, etc.)
- More sophisticated parsing logic
- Additional normalization rules
- Error handling and validation
- Unit tests

## License

Internal use only.
