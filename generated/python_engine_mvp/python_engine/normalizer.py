"""Normalizer module for item names and cost type classification."""

import re


def normalize_item_name(raw_name: str) -> str:
    """Normalize item names to standard format.
    
    Args:
        raw_name: Raw item name from invoice
        
    Returns:
        Normalized item name
    """
    raw_name_lower = raw_name.lower()
    
    # Wiper blade normalization
    wiper_keywords = ['ワイパー', 'wiper', 'ブレード']
    for keyword in wiper_keywords:
        if keyword in raw_name_lower:
            return 'wiper_blade'
    
    # Return original if no normalization rule matches
    return raw_name


def classify_cost_type(item_name: str) -> str:
    """Classify item as parts or labor.
    
    Args:
        item_name: Item name (raw or normalized)
        
    Returns:
        Cost type: 'parts' or 'labor'
    """
    # Labor classification
    if '工賃' in item_name:
        return 'labor'
    
    # Default to parts
    return 'parts'
