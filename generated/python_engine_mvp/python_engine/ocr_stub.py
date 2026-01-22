"""OCR stub module.

Returns mock OCR results for testing purposes.
In production, this would integrate with actual OCR services.
"""


def ocr_extract_text(pdf_path: str) -> str:
    """Extract text from PDF using OCR.
    
    Args:
        pdf_path: Path to the PDF file
        
    Returns:
        Extracted text as string (stub data for now)
    """
    # Stub implementation returns mock invoice data
    stub_text = """株式会社サンプル自動車
見積日: 2024-01-15

品目:
1. ワイパーブレード交換 3,500円
2. エンジンオイル 4L 8,000円
3. オイルフィルター 1,200円
4. オイル交換工賃 2,000円
5. ブレーキパッド 12,000円
6. ブレーキパッド交換工賃 5,000円

小計（税抜）: 31,700円
消費税（10%）: 3,170円
合計（税込）: 34,870円
"""
    return stub_text
