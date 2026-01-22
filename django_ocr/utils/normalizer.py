"""
Product name normalization utilities
"""
import re


class ProductNameNormalizer:
    """
    Normalizes product names according to business rules
    """

    # Normalization rules mapping
    NORMALIZATION_RULES = {
        'wiper_blade': [
            'ワイパー',
            'wiper',
            'ブレード',
            'blade',
            'ワイパーブレード',
            'wiper blade',
        ],
        'engine_oil': [
            'エンジンオイル',
            'engine oil',
            'オイル',
            'oil',
            'エンジン油',
        ],
        'air_filter': [
            'エアフィルター',
            'air filter',
            'エアクリーナー',
            'air cleaner',
        ],
        'oil_filter': [
            'オイルフィルター',
            'oil filter',
            'オイルエレメント',
            'oil element',
        ],
        'brake_pad': [
            'ブレーキパッド',
            'brake pad',
            'ブレーキ',
            'brake',
        ],
        'tire': [
            'タイヤ',
            'tire',
            'tyre',
        ],
        'battery': [
            'バッテリー',
            'battery',
            '蓄電池',
        ],
    }

    LABOR_KEYWORDS = [
        '工賃',
        'labor',
        'labour',
        'installation',
        'service',
        '取付',
        '取り付け',
        '交換工賃',
        '作業',
        '手数料',
    ]

    @classmethod
    def normalize(cls, raw_name: str) -> str:
        """
        Normalize product name to standard category

        Args:
            raw_name: Raw product name from OCR

        Returns:
            Normalized product name (e.g., 'wiper_blade', 'engine_oil')
        """
        if not raw_name:
            return 'unknown'

        lower_name = raw_name.lower().strip()

        # Check each normalization rule
        for normalized_name, keywords in cls.NORMALIZATION_RULES.items():
            for keyword in keywords:
                if keyword.lower() in lower_name:
                    return normalized_name

        # If no match found, create a safe normalized name
        # Remove special characters and replace spaces with underscore
        safe_name = re.sub(r'[^\w\s]', '', lower_name)
        safe_name = re.sub(r'\s+', '_', safe_name)

        return safe_name or 'unknown'

    @classmethod
    def determine_cost_type(cls, raw_name: str) -> str:
        """
        Determine if item is parts or labor

        Args:
            raw_name: Raw product name from OCR

        Returns:
            'labor' or 'parts'
        """
        if not raw_name:
            return 'parts'

        lower_name = raw_name.lower().strip()

        # Check if name contains labor keywords
        for keyword in cls.LABOR_KEYWORDS:
            if keyword.lower() in lower_name:
                return 'labor'

        return 'parts'

    @classmethod
    def extract_quantity(cls, text: str) -> int:
        """
        Extract quantity from text (e.g., "x2", "2個", "2本")

        Args:
            text: Text containing quantity

        Returns:
            Quantity as integer (default 1)
        """
        # Pattern: x2, ×2, 2個, 2本, etc.
        patterns = [
            r'[x×](\d+)',
            r'(\d+)[個本枚]',
            r'数量[:\s]*(\d+)',
        ]

        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                try:
                    return int(match.group(1))
                except (ValueError, IndexError):
                    continue

        return 1
