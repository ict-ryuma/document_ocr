#!/usr/bin/env python3
import sys
import json
import os
import argparse
from datetime import date

def normalize_item_name(raw_name):
    """
    Normalize item names according to MVP rules.
    """
    lower = raw_name.lower()
    
    # Wiper blade normalization
    if any(keyword in lower for keyword in ['ワイパー', 'wiper', 'ブレード', 'blade']):
        return 'wiper_blade'
    
    # Engine oil normalization
    if any(keyword in lower for keyword in ['エンジンオイル', 'engine oil', 'oil']):
        return 'engine_oil'
    
    # Default: use raw name with spaces replaced
    return raw_name.lower().replace(' ', '_').replace('　', '_')

def determine_cost_type(item_name_raw):
    """
    Determine if item is parts or labor.
    If name includes 工賃 or 'labor' or 'installation' -> labor
    Otherwise -> parts
    """
    lower = item_name_raw.lower()
    if any(keyword in lower for keyword in ['工賃', 'labor', 'installation', 'service']):
        return 'labor'
    return 'parts'

def parse_pdf(pdf_path):
    """
    MVP PDF parser (stateless).
    - If file doesn't exist: return error
    - If file exists: return sample/dummy data
    """
    if not os.path.exists(pdf_path):
        return {"error": f"File not found: {pdf_path}"}
    
    # For MVP: return fixed sample data
    raw_items = [
        {"name": "ワイパーブレード", "amount": 3800},
        {"name": "ワイパー交換工賃", "amount": 2200},
        {"name": "エンジンオイル 5W-30", "amount": 4800},
        {"name": "オイル交換工賃", "amount": 1500},
        {"name": "エアフィルター", "amount": 2800}
    ]
    
    items = []
    for raw_item in raw_items:
        normalized = normalize_item_name(raw_item["name"])
        cost_type = determine_cost_type(raw_item["name"])
        items.append({
            "item_name_raw": raw_item["name"],
            "item_name_norm": normalized,
            "cost_type": cost_type,
            "amount_excl_tax": raw_item["amount"]
        })
    
    total_excl_tax = sum(item["amount_excl_tax"] for item in items)
    total_incl_tax = int(total_excl_tax * 1.1)
    
    result = {
        "vendor_name": "Sample Auto Shop",
        "estimate_date": date.today().isoformat(),
        "total_excl_tax": total_excl_tax,
        "total_incl_tax": total_incl_tax,
        "items": items
    }
    
    return result

def main():
    parser = argparse.ArgumentParser(description='PDF Estimate Parser')
    parser.add_argument('--pdf', required=True, help='Path to PDF file')
    args = parser.parse_args()
    
    result = parse_pdf(args.pdf)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0)

if __name__ == '__main__':
    main()