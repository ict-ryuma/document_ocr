# Rails Estimate Parser MVP

Rails API + Python PDF parser + kintone integration.

## Prerequisites

- Ruby 3.x
- Rails 7.x
- Python 3.x
- SQLite3

## Setup

```bash
cd rails_app
bundle install
rails db:create db:migrate

# Optional: seed sample data
ruby script/seed_sample.rb

# Set environment variables
export KINTONE_DOMAIN="your-subdomain.cybozu.com"
export KINTONE_API_TOKEN="your-api-token"
```

## Run Server

```bash
rails server
```

## API Endpoints

### 1. Parse PDF and Create Estimate

```bash
curl -X POST http://localhost:3000/estimates/from_pdf \
  -H "Content-Type: application/json" \
  -d '{"pdf_path":"../dummy.pdf"}'
```

Response:
```json
{"estimate_id": 1}
```

### 2. Get Recommendations by Item

```bash
curl "http://localhost:3000/recommendations/by_item?item=wiper_blade"
```

Response:
```json
{
  "single_vendor_best": {
    "estimate_id": 1,
    "vendor_name": "AutoShop A",
    "total": 8500
  },
  "split_theoretical_best": {
    "parts_min": 3500,
    "labor_min": 2000,
    "total": 5500
  },
  "totals_per_estimate": [
    {"estimate_id": 1, "vendor_name": "AutoShop A", "total": 8500},
    {"estimate_id": 2, "vendor_name": "AutoShop B", "total": 9200}
  ]
}
```

### 3. Push to kintone

```bash
curl -X POST "http://localhost:3000/kintone/push?item=wiper_blade"
```

Response:
```json
{"kintone_record_id": "12345"}
```

### 4. List All Estimates

```bash
curl "http://localhost:3000/estimates"
```

Response:
```json
[
  {
    "id": 1,
    "vendor_name": "AutoShop A",
    "estimate_date": "2025-01-15",
    "total_excl_tax": 50000,
    "total_incl_tax": 55000,
    "items_count": 5
  }
]
```

### 5. Natural Language Query (MVP stub)

```bash
curl "http://localhost:3000/nl/query?q=ワイパーで一番安いのは"
```

Response: Same as `/recommendations/by_item?item=wiper_blade`

```bash
curl "http://localhost:3000/nl/query?q=エンジンオイル交換"
```

Response:
```json
{"error": "unsupported query"}
```

## Python Engine

See `../python_engine/README.md` for details.

## Database Schema

**estimates**
- vendor_name: string
- estimate_date: date
- total_excl_tax: integer
- total_incl_tax: integer

**estimate_items**
- estimate_id: references
- item_name_raw: string
- item_name_norm: string
- cost_type: string (parts/labor)
- amount_excl_tax: integer

## Notes

- Python engine is stateless (no DB/file writes)
- Item normalization: ワイパー/wiper/ブレード → wiper_blade
- Cost type: includes 工賃 → labor, else parts
- kintone app_id = 316