"""Parser module for extracting structured data from OCR text."""

import re
from typing import Dict, List, Any


def parse_invoice_data(raw_text: str) -> Dict[str, Any]:
    """Parse invoice data from raw OCR text.
    
    Args:
        raw_text: Raw text extracted from PDF
        
    Returns:
        Dictionary with parsed invoice data
    """
    result = {
        'vendor_name': '',
        'estimate_date': '',
        'total_excl_tax': 0,
        'total_incl_tax': 0,
        'items': []
    }
    
    # Extract vendor name (first line typically)
    lines = raw_text.strip().split('\n')
    if lines:
        result['vendor_name'] = lines[0].strip()
    
    # Extract estimate date
    date_match = re.search(r'見積日[:\s：]+(\d{4}[-/]\d{1,2}[-/]\d{1,2})', raw_text)
    if date_match:
        result['estimate_date'] = date_match.group(1)
    
    # Extract items with amounts
    item_pattern = r'(?:\d+\.\s+)?(.+?)\s+(\d{1,3}(?:,\d{3})*)円'
    items = re.findall(item_pattern, raw_text)
    
    for item_name, amount_str in items:
        item_name = item_name.strip()
        amount = int(amount_str.replace(',', ''))
        
        # Skip total/subtotal lines
        if any(keyword in item_name for keyword in ['小計', '合計', '消費税']):
            continue
        
        result['items'].append({
            'item_name_raw': item_name,
            'amount_excl_tax': amount
        })
    
    # Extract totals
    total_excl_match = re.search(r'小計[^\d]*(\d{1,3}(?:,\d{3})*)円', raw_text)
    if total_excl_match:
        result['total_excl_tax'] = int(total_excl_match.group(1).replace(',', ''))
    
    total_incl_match = re.search(r'合計[^\d]*(\d{1,3}(?:,\d{3})*)円', raw_text)
    if total_incl_match:
        result['total_incl_tax'] = int(total_incl_match.group(1).replace(',', ''))
    
    return result
