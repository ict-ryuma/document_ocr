"""
Google Vision API OCR integration
"""
import os
import io
import re
from typing import List, Dict, Optional
from datetime import datetime

from google.cloud import vision
from pdf2image import convert_from_path
from PIL import Image


class VisionOCR:
    """
    Google Cloud Vision API OCR processor
    """

    def __init__(self):
        """Initialize Vision API client"""
        credentials_path = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
        if credentials_path and os.path.exists(credentials_path):
            self.client = vision.ImageAnnotatorClient()
        else:
            # For development/testing without credentials
            self.client = None

    def extract_text_from_pdf(self, pdf_path: str) -> str:
        """
        Extract text from PDF using Vision API

        Args:
            pdf_path: Path to PDF file

        Returns:
            Extracted text content
        """
        if not os.path.exists(pdf_path):
            raise FileNotFoundError(f"PDF file not found: {pdf_path}")

        # Convert PDF to images
        try:
            images = convert_from_path(pdf_path, dpi=300)
        except Exception as e:
            raise Exception(f"Failed to convert PDF to images: {str(e)}")

        all_text = []

        # Process each page
        for i, image in enumerate(images):
            try:
                text = self._extract_text_from_image(image)
                if text:
                    all_text.append(f"--- Page {i + 1} ---\n{text}")
            except Exception as e:
                print(f"Warning: Failed to process page {i + 1}: {str(e)}")
                continue

        return "\n\n".join(all_text)

    def _extract_text_from_image(self, image: Image.Image) -> str:
        """
        Extract text from a single image using Vision API

        Args:
            image: PIL Image object

        Returns:
            Extracted text
        """
        if not self.client:
            # Return dummy text for testing without credentials
            return self._get_dummy_text()

        # Convert PIL Image to bytes
        img_byte_arr = io.BytesIO()
        image.save(img_byte_arr, format='PNG')
        img_byte_arr = img_byte_arr.getvalue()

        # Create Vision API image object
        vision_image = vision.Image(content=img_byte_arr)

        # Perform OCR
        response = self.client.text_detection(image=vision_image)

        if response.error.message:
            raise Exception(f"Vision API error: {response.error.message}")

        # Extract text from response
        texts = response.text_annotations
        if texts:
            return texts[0].description
        else:
            return ""

    def _get_dummy_text(self) -> str:
        """
        Return dummy estimate text for testing without Google credentials
        """
        return """
見積書

株式会社サンプル自動車
〒100-0001 東京都千代田区千代田1-1
TEL: 03-1234-5678

見積日: 2025年1月19日
見積番号: EST-2025-001

品名                        金額
ワイパーブレード            ¥3,800
ワイパー交換工賃            ¥2,200
エンジンオイル 5W-30        ¥4,800
オイル交換工賃              ¥1,500
エアフィルター              ¥2,800

小計                        ¥15,100
消費税(10%)                 ¥1,510
合計                        ¥16,610
"""


class EstimateParser:
    """
    Parse estimate text into structured data
    """

    @staticmethod
    def parse(text: str, vendor_name: Optional[str] = None) -> Dict:
        """
        Parse OCR text into structured estimate data

        Args:
            text: OCR extracted text
            vendor_name: Override vendor name (optional)

        Returns:
            Dict with vendor_name, estimate_date, items, totals
        """
        lines = [line.strip() for line in text.split('\n') if line.strip()]

        # Extract vendor name
        extracted_vendor = EstimateParser._extract_vendor_name(lines)
        final_vendor = vendor_name or extracted_vendor or "Unknown Vendor"

        # Extract estimate date
        estimate_date = EstimateParser._extract_date(lines)

        # Extract line items
        items = EstimateParser._extract_items(lines)

        # Calculate totals
        total_excl_tax = sum(item['amount_excl_tax'] for item in items)
        total_incl_tax = int(total_excl_tax * 1.1)

        return {
            'vendor_name': final_vendor,
            'estimate_date': estimate_date,
            'total_excl_tax': total_excl_tax,
            'total_incl_tax': total_incl_tax,
            'items': items,
        }

    @staticmethod
    def _extract_vendor_name(lines: List[str]) -> str:
        """Extract vendor name from text lines"""
        for line in lines[:10]:  # Check first 10 lines
            # Look for company name patterns
            if '株式会社' in line or '有限会社' in line or '合同会社' in line:
                return line.strip()
            if 'auto' in line.lower() or 'motor' in line.lower():
                return line.strip()
        return "Unknown Vendor"

    @staticmethod
    def _extract_date(lines: List[str]) -> str:
        """Extract estimate date from text"""
        date_patterns = [
            r'(\d{4})年(\d{1,2})月(\d{1,2})日',
            r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})',
        ]

        for line in lines[:20]:  # Check first 20 lines
            for pattern in date_patterns:
                match = re.search(pattern, line)
                if match:
                    try:
                        year, month, day = match.groups()
                        return f"{year}-{int(month):02d}-{int(day):02d}"
                    except (ValueError, IndexError):
                        continue

        # Default to today
        return datetime.now().strftime('%Y-%m-%d')

    @staticmethod
    def _extract_items(lines: List[str]) -> List[Dict]:
        """Extract line items from text"""
        items = []
        amount_pattern = r'[¥￥]?\s*([0-9,]+)'

        for line in lines:
            # Skip header lines
            if any(keyword in line for keyword in ['見積', '品名', '金額', '小計', '合計', '消費税', 'TEL', '〒', 'FAX']):
                continue

            # Look for lines with amounts
            match = re.search(amount_pattern, line)
            if match:
                try:
                    # Extract amount
                    amount_str = match.group(1).replace(',', '')
                    amount = int(amount_str)

                    # Skip if amount is too large (likely a total)
                    if amount > 1000000:
                        continue

                    # Extract item name (text before the amount)
                    item_name = line[:match.start()].strip()
                    if len(item_name) < 2:  # Skip if name too short
                        continue

                    items.append({
                        'item_name_raw': item_name,
                        'amount_excl_tax': amount,
                    })
                except (ValueError, IndexError):
                    continue

        return items
