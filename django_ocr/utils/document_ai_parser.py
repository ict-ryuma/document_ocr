"""
Google Cloud Document AI integration for invoice/estimate parsing
Form Parser processor with LLM-based extraction
"""
import os
import re
from typing import List, Dict, Optional
from datetime import datetime
from decimal import Decimal

from google.cloud import documentai_v1 as documentai
from google.api_core.client_options import ClientOptions
from .azure_openai_client import AzureOpenAIClient


class DocumentAIParser:
    """
    Google Cloud Document AI Form Parser integration
    """

    def __init__(self):
        """Initialize Document AI client and Azure OpenAI client"""
        self.project_id = os.environ.get('GCP_PROJECT_ID', 'your-project-id')
        self.location = os.environ.get('DOCUMENT_AI_LOCATION', 'us')
        self.processor_id = os.environ.get('DOCUMENT_AI_PROCESSOR_ID', '6b217be4de9ac23f')

        # Initialize Document AI client
        credentials_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if credentials_path and os.path.exists(credentials_path):
            opts = ClientOptions(api_endpoint=f"{self.location}-documentai.googleapis.com")
            self.client = documentai.DocumentProcessorServiceClient(client_options=opts)
            self.processor_name = self.client.processor_path(
                self.project_id, self.location, self.processor_id
            )
        else:
            # For testing without credentials
            self.client = None
            self.processor_name = None

        # Initialize Azure OpenAI client for LLM-based extraction
        self.llm_client = AzureOpenAIClient()

    def process_document(self, pdf_path: str) -> documentai.Document:
        """
        Process PDF using Document AI Form Parser

        Args:
            pdf_path: Path to PDF file

        Returns:
            Document AI Document object
        """
        if not self.client:
            raise Exception("Document AI client not initialized - check credentials")

        if not os.path.exists(pdf_path):
            raise FileNotFoundError(f"PDF file not found: {pdf_path}")

        # Read the file
        with open(pdf_path, "rb") as pdf_file:
            file_content = pdf_file.read()

        # Configure the process request
        raw_document = documentai.RawDocument(
            content=file_content,
            mime_type="application/pdf"
        )

        # Make the request
        request = documentai.ProcessRequest(
            name=self.processor_name,
            raw_document=raw_document
        )

        result = self.client.process_document(request=request)

        return result.document

    def extract_estimate_data(self, pdf_path: str, vendor_name: Optional[str] = None) -> Dict:
        """
        Extract structured estimate data from PDF using GPT-4o Vision API

        Args:
            pdf_path: Path to PDF file
            vendor_name: Override vendor name (optional)

        Returns:
            Dict with vendor_name, estimate_date, items, totals
        """
        try:
            # === PRIMARY STRATEGY: GPT-4o VISION API ===
            print("=" * 80)
            print("EXTRACTION STRATEGY: GPT-4o Vision (Image-based)")
            print("=" * 80)

            # Extract items and totals using Vision API
            vision_result = self.llm_client.extract_invoice_items_from_image(pdf_path)

            if vision_result and vision_result.get('items') and len(vision_result['items']) > 0:
                items = vision_result['items']
                print(f"✓ Vision API successfully extracted {len(items)} items")

                # Use AI-extracted totals (primary), fallback to sum() if not available
                ai_total_excl_tax = vision_result.get('total_amount_excl_tax')
                ai_total_incl_tax = vision_result.get('total_amount_incl_tax')

                if ai_total_excl_tax is not None:
                    print(f"✓ Using AI-extracted total (excl tax): {ai_total_excl_tax}")
                    total_excl_tax = ai_total_excl_tax
                else:
                    print("⚠ AI did not extract total_excl_tax, calculating from items")
                    total_excl_tax = sum(item['amount_excl_tax'] for item in items)

                if ai_total_incl_tax is not None:
                    print(f"✓ Using AI-extracted total (incl tax): {ai_total_incl_tax}")
                    total_incl_tax = ai_total_incl_tax
                else:
                    print("⚠ AI did not extract total_incl_tax, calculating as 110% of excl_tax")
                    total_incl_tax = int(total_excl_tax * 1.1)

                return {
                    'vendor_name': vendor_name or 'Unknown Vendor',
                    'estimate_date': '2026-01-22',  # Default date for now
                    'total_excl_tax': total_excl_tax,
                    'total_incl_tax': total_incl_tax,
                    'items': items,
                    'raw_text': 'Extracted via Vision API',
                }

            print("✗ Vision API extraction failed")

            # === FALLBACK: DOCUMENT AI (OCR-based) ===
            print("=" * 80)
            print("FALLBACK STRATEGY: Document AI (OCR-based)")
            print("=" * 80)

            if not self.client:
                # Fallback to dummy data if no credentials
                return self._get_dummy_estimate_data(vendor_name)

            # Process document
            document = self.process_document(pdf_path)

            # Extract form fields
            form_fields = self._extract_form_fields(document)

            # Extract text and tables
            full_text = document.text
            tables = self._extract_tables(document)

            # Parse estimate data
            parsed_vendor = vendor_name or self._extract_vendor_name(form_fields, full_text)
            parsed_date = self._extract_estimate_date(form_fields, full_text)
            items = self._extract_line_items(tables, full_text)

            # Calculate totals
            total_excl_tax = sum(item['amount_excl_tax'] for item in items)
            total_incl_tax = int(total_excl_tax * 1.1)

            return {
                'vendor_name': parsed_vendor,
                'estimate_date': parsed_date,
                'total_excl_tax': total_excl_tax,
                'total_incl_tax': total_incl_tax,
                'items': items,
                'raw_text': full_text[:1000],  # First 1000 chars for reference
            }

        except Exception as e:
            print(f"All extraction strategies failed: {e}, using dummy data")
            import traceback
            traceback.print_exc()
            return self._get_dummy_estimate_data(vendor_name)

    def _extract_form_fields(self, document: documentai.Document) -> Dict[str, str]:
        """Extract key-value pairs from form fields"""
        form_fields = {}

        for page in document.pages:
            if not hasattr(page, 'form_fields'):
                continue

            for field in page.form_fields:
                # Get field name
                field_name = self._get_text(field.field_name, document.text)
                # Get field value
                field_value = self._get_text(field.field_value, document.text)

                if field_name and field_value:
                    form_fields[field_name.strip()] = field_value.strip()

        return form_fields

    def _extract_tables(self, document: documentai.Document) -> List[List[List[str]]]:
        """Extract tables from document"""
        tables = []

        for page in document.pages:
            if not hasattr(page, 'tables'):
                continue

            for table in page.tables:
                table_data = []

                for row in table.body_rows:
                    row_data = []
                    for cell in row.cells:
                        cell_text = self._get_text(cell.layout, document.text)
                        row_data.append(cell_text.strip())
                    table_data.append(row_data)

                tables.append(table_data)

        return tables

    def _get_text(self, layout, full_text: str) -> str:
        """Extract text from layout object"""
        if not layout or not hasattr(layout, 'text_anchor'):
            return ""

        text_anchor = layout.text_anchor
        if not text_anchor or not hasattr(text_anchor, 'text_segments'):
            return ""

        text_segments = text_anchor.text_segments
        if not text_segments:
            return ""

        # Concatenate text segments
        result = ""
        for segment in text_segments:
            start = int(segment.start_index) if hasattr(segment, 'start_index') else 0
            end = int(segment.end_index) if hasattr(segment, 'end_index') else len(full_text)
            result += full_text[start:end]

        return result

    def _extract_vendor_name(self, form_fields: Dict, full_text: str) -> str:
        """Extract vendor name from form fields or text"""
        # Try form fields first
        for key in ['会社名', '業者名', '店舗名', 'Company', 'Vendor']:
            if key in form_fields:
                return form_fields[key]

        # Try pattern matching
        lines = full_text.split('\n')
        for line in lines[:10]:
            if '株式会社' in line or '有限会社' in line or '合同会社' in line:
                return line.strip()

        return "Unknown Vendor"

    def _extract_estimate_date(self, form_fields: Dict, full_text: str) -> str:
        """Extract estimate date"""
        # Try form fields
        for key in ['見積日', '日付', 'Date', '作成日']:
            if key in form_fields:
                date_str = form_fields[key]
                parsed = self._parse_date(date_str)
                if parsed:
                    return parsed

        # Try pattern matching
        date_patterns = [
            r'(\d{4})年(\d{1,2})月(\d{1,2})日',
            r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})',
        ]

        for line in full_text.split('\n')[:20]:
            for pattern in date_patterns:
                match = re.search(pattern, line)
                if match:
                    try:
                        year, month, day = match.groups()
                        return f"{year}-{int(month):02d}-{int(day):02d}"
                    except (ValueError, IndexError):
                        continue

        return datetime.now().strftime('%Y-%m-%d')

    def _parse_date(self, date_str: str) -> Optional[str]:
        """Parse date string to YYYY-MM-DD format"""
        patterns = [
            (r'(\d{4})年(\d{1,2})月(\d{1,2})日', lambda m: f"{m[0]}-{int(m[1]):02d}-{int(m[2]):02d}"),
            (r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})', lambda m: f"{m[0]}-{int(m[1]):02d}-{int(m[2]):02d}"),
        ]

        for pattern, formatter in patterns:
            match = re.search(pattern, date_str)
            if match:
                try:
                    return formatter(match.groups())
                except (ValueError, IndexError):
                    continue

        return None

    def _extract_line_items(self, tables: List, full_text: str) -> List[Dict]:
        """
        Extract line items from tables and text using LLM-first approach

        Architecture:
        1. Try LLM (Azure OpenAI GPT-4o) - semantic understanding
        2. Fallback to regex if LLM fails - rule-based extraction

        Returns normalized format:
        [
            {
                "item_name_raw": "ワイパーブレード",
                "amount_excl_tax": 3800,
                "quantity": 1
            },
            ...
        ]
        """
        items = []

        # === STRATEGY 1: LLM-BASED EXTRACTION (PREFERRED) ===
        print("="*60)
        print("EXTRACTION STRATEGY 1: Azure OpenAI (GPT-4o)")
        print("="*60)

        llm_items = self.llm_client.extract_invoice_items(full_text)

        if llm_items and len(llm_items) > 0:
            print(f"✓ LLM successfully extracted {len(llm_items)} items")
            return llm_items

        print("✗ LLM extraction failed or returned no items")

        # === STRATEGY 2: TABLE-BASED EXTRACTION (FALLBACK 1) ===
        print("="*60)
        print("EXTRACTION STRATEGY 2: Table Parsing (Fallback)")
        print("="*60)

        print(f"DEBUG: Found {len(tables)} tables in document")
        for i, table in enumerate(tables):
            table_items = self._parse_table_items(table)
            print(f"DEBUG: Table {i} extracted {len(table_items)} items")
            items.extend(table_items)

        if items:
            print(f"✓ Table extraction succeeded: {len(items)} items")
            return items

        # === STRATEGY 3: REGEX TEXT PARSING (FALLBACK 2) ===
        print("="*60)
        print("EXTRACTION STRATEGY 3: Regex Text Parsing (Last Resort)")
        print("="*60)

        items = self._parse_text_items(full_text)
        print(f"DEBUG: Text parsing extracted {len(items)} items")

        if items:
            print(f"✓ Regex extraction succeeded: {len(items)} items")
            print(f"DEBUG: First item from text: {items[0]}")
        else:
            print("✗ All extraction strategies failed")

        return items

    def _parse_table_items(self, table: List[List[str]]) -> List[Dict]:
        """Parse items from table data"""
        items = []

        for row in table:
            if len(row) < 2:
                continue

            # Try to find item name and price
            item_name = None
            amount = None
            quantity = 1

            for cell in row:
                # Try to extract price (numbers with yen symbol or commas)
                price_match = re.search(r'[¥￥]?\s*([0-9,]+)', cell)
                if price_match and not amount:
                    try:
                        amount = int(price_match.group(1).replace(',', ''))
                    except ValueError:
                        continue

                # If not a number, might be item name
                elif not item_name and len(cell) > 2 and not re.match(r'^[\d,¥￥\s]+$', cell):
                    item_name = cell

                # Try to extract quantity
                qty_match = re.search(r'[x×]?\s*(\d+)\s*[個本枚]?', cell)
                if qty_match:
                    try:
                        quantity = int(qty_match.group(1))
                    except ValueError:
                        pass

            if item_name and amount:
                # Skip if amount is too large (likely a total)
                if amount > 1000000:
                    continue

                items.append({
                    'item_name_raw': item_name.strip(),
                    'amount_excl_tax': amount,
                    'quantity': quantity
                })

        return items

    def _parse_text_items(self, full_text: str) -> List[Dict]:
        """
        Parse items from plain text with enhanced regex patterns
        - Supports multiple amounts per line (re.finditer)
        - Handles comma+space in numbers (133, 934 -> 133934)
        - Filters out total amounts
        """
        items = []
        lines = full_text.split('\n')

        print(f"DEBUG: _parse_text_items processing {len(lines)} lines")

        for idx, line in enumerate(lines):
            # Clean line: remove comma+space pattern (e.g., "133, 934" -> "133,934")
            cleaned_line = re.sub(r'(\d),\s+(\d)', r'\1,\2', line)
            print(f"DEBUG: Line {idx}: {cleaned_line[:100]}")  # First 100 chars

            # === PATTERN-BASED NOISE FILTERING (GENERIC) ===

            # 1. Check for phone number pattern (XX-XXXX-XXXX or XXX-XXX-XXXX)
            phone_pattern = r'\d{2,4}[-\s]\d{2,4}[-\s]\d{4}'
            if re.search(phone_pattern, cleaned_line):
                print(f"DEBUG:   Skipped (phone number pattern detected)")
                continue

            # 2. Check for postal code pattern (〒XXX-XXXX)
            postal_pattern = r'〒\s*\d{3}[-\s]\d{4}'
            if re.search(postal_pattern, cleaned_line):
                print(f"DEBUG:   Skipped (postal code pattern detected)")
                continue

            # 3. Check for URL/email pattern
            if re.search(r'(https?://|www\.|@[\w\.-]+\.(com|jp|net|org))', cleaned_line, re.IGNORECASE):
                print(f"DEBUG:   Skipped (URL/email pattern detected)")
                continue

            # 4. GENERIC SKIP KEYWORDS (language-agnostic where possible)
            generic_skip_keywords = [
                # Totals and summaries (common across languages)
                '合計', '小計', 'Total', 'Subtotal', 'Sum', '総額',
                # Tax-related
                '消費税', 'Tax', 'VAT', '税込', '税抜', '課税',
                # Contact/Document metadata
                'TEL', 'Tel', 'FAX', 'Fax', 'Phone', 'E-mail', 'Email',
                # Document identifiers
                'No.', 'No ', 'ID:', 'ID ', '番号',
                # Headers
                '品名', '金額', '単価', 'Item', 'Amount', 'Price', 'Qty', 'Quantity',
            ]

            should_skip = False
            for kw in generic_skip_keywords:
                if kw in cleaned_line:
                    print(f"DEBUG:   Skipped (generic keyword: '{kw}')")
                    should_skip = True
                    break

            if should_skip:
                continue

            # Skip very short lines (likely not item descriptions)
            if len(cleaned_line.strip()) < 3:
                print(f"DEBUG:   Skipped (too short)")
                continue

            # === GENERIC PRICE EXTRACTION PATTERNS ===
            # Strategy: Use negative lookbehind/lookahead to exclude IDs and phone numbers
            # (?<![\d-]) = NOT preceded by digit or hyphen (excludes "SJ5-056597" style IDs)
            # (?![\d-])  = NOT followed by digit or hyphen (excludes "048-754-2040" style phones)

            price_patterns = [
                # Currency-marked patterns (high confidence - always valid)
                r'[¥￥$]\s*([0-9,]+)',                                    # ¥1,000 or $1,000
                r'([0-9,]+)\s*[円元]',                                     # 1,000円 or 1,000元

                # Generic number patterns (only if NOT part of ID/phone)
                r'(?<![\d-])([0-9]{1,3},[0-9]{3}(?:,[0-9]{3})*)(?![\d-])',  # Comma-separated (1,000 or 100,000)
                r'(?<![\d-])([0-9]{4,})(?![\d-])',                       # 4+ digits standalone
            ]

            print(f"DEBUG:   Searching for prices (generic patterns, excluding IDs/phones)")

            # Use finditer to get ALL matches in this line
            all_matches = []
            for pattern in price_patterns:
                matches = list(re.finditer(pattern, cleaned_line))
                if matches:
                    all_matches.extend(matches)
                    print(f"DEBUG:   Found {len(matches)} match(es) with pattern: {pattern}")

            # Remove duplicate matches (same position)
            seen_positions = set()
            unique_matches = []
            for match in all_matches:
                pos = (match.start(), match.end())
                if pos not in seen_positions:
                    seen_positions.add(pos)
                    unique_matches.append(match)

            if unique_matches:
                print(f"DEBUG:   Total unique matches in line: {len(unique_matches)}")

            # Process each price match in this line
            for match_num, price_match in enumerate(unique_matches):
                try:
                    # Extract and clean the amount
                    amount_str = price_match.group(1).replace(',', '').strip()
                    amount = int(amount_str)
                    print(f"DEBUG:   Match {match_num + 1}: Extracted amount: {amount}")

                    # Skip if too large or too small
                    if amount > 1000000 or amount < 100:
                        print(f"DEBUG:   Skipped (amount out of range: {amount})")
                        continue

                    # Extract item name (text before this price match)
                    item_name = cleaned_line[:price_match.start()].strip()

                    # If multiple prices on same line, try to get text after previous match
                    if match_num > 0:
                        prev_match = unique_matches[match_num - 1]
                        item_name = cleaned_line[prev_match.end():price_match.start()].strip()
                        print(f"DEBUG:   Multiple prices detected, item name between: '{item_name}'")

                    # Clean up item name (remove trailing symbols like +)
                    item_name = re.sub(r'[+\-\s]+$', '', item_name).strip()

                    # If item name is too short or empty, use fallback
                    if len(item_name) < 2:
                        print(f"DEBUG:   Item name too short: '{item_name}', using fallback")
                        item_name = "見積明細一式"

                    print(f"DEBUG:   Item name: '{item_name}'")

                    # Extract quantity if present
                    quantity = 1
                    qty_patterns = [
                        r'[x×]\s*(\d+)',            # x2, ×3
                        r'(\d+)\s*[個本枚台式]',     # 2個, 3本
                        r'数量\s*[:：]?\s*(\d+)',    # 数量:2
                    ]

                    for qty_pattern in qty_patterns:
                        qty_match = re.search(qty_pattern, cleaned_line)
                        if qty_match:
                            try:
                                quantity = int(qty_match.group(1))
                                print(f"DEBUG:   Quantity found: {quantity}")
                                break
                            except ValueError:
                                pass

                    items.append({
                        'item_name_raw': item_name,
                        'amount_excl_tax': amount,
                        'quantity': quantity,
                        'line_number': idx  # Track line number for debugging
                    })
                    print(f"DEBUG:   ✓ Item added: {item_name} - ¥{amount}")

                except (ValueError, IndexError) as e:
                    print(f"DEBUG:   Error parsing match: {e}")
                    continue

        print(f"DEBUG: Total items before total filtering: {len(items)}")

        # Filter out total amounts
        # Strategy: If an item's amount equals (or is very close to) the sum of other items,
        # it's likely the total line that was mistakenly captured
        if len(items) > 1:
            items_with_sum = []
            for i, item in enumerate(items):
                # Calculate sum of all OTHER items
                other_items = [it for j, it in enumerate(items) if j != i]
                sum_of_others = sum(it['amount_excl_tax'] for it in other_items)

                # Check if this item's amount matches the sum (within 5% tolerance)
                tolerance = sum_of_others * 0.05
                is_total = abs(item['amount_excl_tax'] - sum_of_others) <= tolerance

                if is_total:
                    print(f"DEBUG: Item '{item['item_name_raw']}' (¥{item['amount_excl_tax']}) looks like TOTAL, removing")
                    print(f"DEBUG:   Sum of others: ¥{sum_of_others}, difference: ¥{abs(item['amount_excl_tax'] - sum_of_others)}")
                else:
                    items_with_sum.append(item)

            items = items_with_sum

        # Remove line_number field before returning
        for item in items:
            item.pop('line_number', None)

        print(f"DEBUG: Final items after total filtering: {len(items)}")

        # MERGE DUPLICATE ITEMS
        # If same item_name_raw AND same amount_excl_tax, merge them (sum quantities)
        if len(items) > 1:
            merged_items = {}
            for item in items:
                key = (item['item_name_raw'], item['amount_excl_tax'])
                if key in merged_items:
                    # Duplicate found - merge by adding quantity
                    merged_items[key]['quantity'] += item['quantity']
                    print(f"DEBUG: Merged duplicate: {item['item_name_raw']} ¥{item['amount_excl_tax']}")
                else:
                    merged_items[key] = item.copy()

            items = list(merged_items.values())
            print(f"DEBUG: Items after deduplication: {len(items)}")

        # If no items found after all filtering, create a fallback item
        if not items:
            print("DEBUG: No items extracted, creating fallback")
            # Try to find any large number that might be total
            total_match = re.search(r'[¥￥]?\s*([0-9,]+)\s*円?', full_text)
            if total_match:
                try:
                    amount = int(total_match.group(1).replace(',', ''))
                    if amount >= 1000:  # Reasonable minimum
                        items.append({
                            'item_name_raw': '見積明細一式',
                            'amount_excl_tax': amount,
                            'quantity': 1
                        })
                        print(f"DEBUG: Fallback item created with amount: {amount}")
                except ValueError:
                    pass

        return items

    def _get_dummy_estimate_data(self, vendor_name: Optional[str] = None) -> Dict:
        """Return dummy data for testing"""
        return {
            'vendor_name': vendor_name or "サンプル自動車",
            'estimate_date': datetime.now().strftime('%Y-%m-%d'),
            'total_excl_tax': 15100,
            'total_incl_tax': 16610,
            'items': [
                {
                    'item_name_raw': 'ワイパーブレード',
                    'amount_excl_tax': 3800,
                    'quantity': 1
                },
                {
                    'item_name_raw': 'ワイパー交換工賃',
                    'amount_excl_tax': 2200,
                    'quantity': 1
                },
                {
                    'item_name_raw': 'エンジンオイル 5W-30',
                    'amount_excl_tax': 4800,
                    'quantity': 1
                },
                {
                    'item_name_raw': 'オイル交換工賃',
                    'amount_excl_tax': 1500,
                    'quantity': 1
                },
                {
                    'item_name_raw': 'エアフィルター',
                    'amount_excl_tax': 2800,
                    'quantity': 1
                }
            ],
            'raw_text': '見積書サンプルデータ'
        }
