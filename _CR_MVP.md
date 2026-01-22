You must generate a working MVP for: Rails (API + DB + SQL aggregation + kintone push) and Python (stateless PDF parser stub).

## Tech stack fixed
- Rails API app (SQLite in development)
- Python engine called from Rails via shell command
- kintone REST API push (app_id=316), token/domain loaded from ENV

## Goals (MVP finish line)
1) POST /estimates/from_pdf (body: {"pdf_path":"../dummy.pdf"})
   - Rails calls python_engine/main.py --pdf <path>
   - Rails persists Estimate + EstimateItems
   - Returns {estimate_id: ...}

2) GET /recommendations/by_item?item=wiper_blade
   - Returns:
     - single vendor best (same estimate total min)
     - split theoretical best (parts min + labor min)
     - list totals per estimate (asc)

3) POST /kintone/push?item=wiper_blade
   - Rails computes recommendations and pushes 1 record to kintone
   - Returns {kintone_record_id: "..."} on success

4) GET /estimates
   - Returns list with items_count and totals

5) Natural language: for now, do NOT call LLM.
   - Provide a Rails endpoint GET /nl/query?q=...
   - Minimal rule-based mapping:
     If q includes "一番安い" and an item keyword (ワイパー/wiper/ブレード => wiper_blade), return the same JSON as /recommendations/by_item
     Otherwise return {error:"unsupported query"}

## Python responsibilities (strict)
- Stateless. NO DB, NO kintone, NO file write.
- If pdf path does not exist -> output {"error":"File not found: ..."} and exit 0
- For MVP: if file exists but is dummy/empty, return fixed sample JSON like:
  vendor_name, estimate_date, totals, items...
- Normalization rules:
  - "ワイパー" / "wiper" / "ブレード" -> wiper_blade
  - if item name includes "工賃" -> cost_type=labor else parts

## Rails data model
estimates: vendor_name:string estimate_date:date total_excl_tax:int total_incl_tax:int
estimate_items: estimate:references item_name_raw:string item_name_norm:string cost_type:string amount_excl_tax:int

## Deliverables
Return ONLY {"files":[...]} and include ONLY necessary files.
Target structure:

rails_app/   (complete rails app generated via rails new --api)
python_engine/main.py
python_engine/README.md

Additionally include in rails_app:
- controllers: estimates, recommendations, kintone, nl
- services: estimate_importer, estimate_price_query, kintone_client
- models with associations
- routes wired
- a short README how to run (commands + curl examples)

IMPORTANT:
You are allowed to include a small script in rails_app/script/seed_sample.rb for creating sample estimate #2 (optional).
