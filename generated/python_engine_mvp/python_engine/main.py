#!/usr/bin/env python3
"""Main entry point for PDF parsing engine.

Usage:
    python python_engine/main.py --pdf <path_to_pdf>

Outputs JSON to stdout with parsed invoice data.
"""

import argparse
import json
import sys
from pathlib import Path

from ocr_stub import ocr_extract_text
from parser import parse_invoice_data
from normalizer import normalize_item_name, classify_cost_type


def main():
    parser = argparse.ArgumentParser(description='Parse PDF invoice and output JSON')
    parser.add_argument('--pdf', required=True, help='Path to PDF file')
    args = parser.parse_args()
    
    pdf_path = Path(args.pdf)
    if not pdf_path.exists():
        print(json.dumps({"error": f"File not found: {pdf_path}"}), file=sys.stderr)
        sys.exit(1)
    
    # Step 1: Extract text from PDF (OCR stub)
    raw_text = ocr_extract_text(str(pdf_path))
    
    # Step 2: Parse invoice data from raw text
    parsed_data = parse_invoice_data(raw_text)
    
    # Step 3: Normalize item names and classify cost types
    normalized_items = []
    for item in parsed_data.get('items', []):
        normalized_item = {
            "item_name_raw": item['item_name_raw'],
            "item_name_norm": normalize_item_name(item['item_name_raw']),
            "cost_type": classify_cost_type(item['item_name_raw']),
            "amount_excl_tax": item['amount_excl_tax']
        }
        normalized_items.append(normalized_item)
    
    # Step 4: Build final output JSON
    output = {
        "vendor_name": parsed_data.get('vendor_name', ''),
        "estimate_date": parsed_data.get('estimate_date', ''),
        "total_excl_tax": parsed_data.get('total_excl_tax', 0),
        "total_incl_tax": parsed_data.get('total_incl_tax', 0),
        "items": normalized_items
    }
    
    # Output JSON to stdout
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
