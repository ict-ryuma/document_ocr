"""
Azure OpenAI Client for Invoice Data Extraction using Vision API
"""
import os
import json
import base64
from typing import Dict, List, Optional
from io import BytesIO
from PIL import Image
from pdf2image import convert_from_path
from openai import AzureOpenAI


class AzureOpenAIClient:
    """Client for Azure OpenAI API with GPT-4o Vision for invoice parsing"""

    def __init__(self):
        self.api_key = os.getenv('AZURE_OPENAI_API_KEY')
        self.endpoint = os.getenv('AZURE_OPENAI_ENDPOINT')
        self.deployment = os.getenv('AZURE_DEPLOYMENT_NAME', 'gpt-4o')
        self.api_version = os.getenv('AZURE_API_VERSION', '2024-12-01-preview')

        if not self.api_key or not self.endpoint:
            print("WARNING: Azure OpenAI credentials not configured. Vision extraction will be skipped.")
            self.client = None
        else:
            # Remove trailing slash from endpoint
            endpoint_clean = self.endpoint.rstrip('/')

            self.client = AzureOpenAI(
                api_key=self.api_key,
                azure_endpoint=endpoint_clean,
                api_version=self.api_version,
            )

    def convert_file_to_base64_image(self, file_path: str) -> Optional[str]:
        """
        Convert PDF or image file to Base64-encoded JPEG image

        Args:
            file_path: Path to PDF or image file

        Returns:
            Base64-encoded image string, or None if conversion fails
        """
        try:
            # Check file extension
            file_ext = file_path.lower().split('.')[-1]

            if file_ext == 'pdf':
                # Convert PDF first page to image
                print(f"DEBUG: Converting PDF to image: {file_path}")
                images = convert_from_path(file_path, first_page=1, last_page=1, dpi=200)

                if not images:
                    print("ERROR: PDF conversion returned no images")
                    return None

                image = images[0]
                print(f"DEBUG: PDF converted to image: {image.size}")

            elif file_ext in ['jpg', 'jpeg', 'png', 'gif', 'bmp']:
                # Load image directly
                print(f"DEBUG: Loading image file: {file_path}")
                image = Image.open(file_path)
                print(f"DEBUG: Image loaded: {image.size}")

            else:
                print(f"ERROR: Unsupported file type: {file_ext}")
                return None

            # Convert to RGB if necessary (for PNG with alpha channel, etc.)
            if image.mode not in ('RGB', 'L'):
                print(f"DEBUG: Converting image mode from {image.mode} to RGB")
                image = image.convert('RGB')

            # Resize if too large (max 2048px on longest side for better performance)
            max_size = 2048
            if max(image.size) > max_size:
                ratio = max_size / max(image.size)
                new_size = tuple(int(dim * ratio) for dim in image.size)
                print(f"DEBUG: Resizing image from {image.size} to {new_size}")
                image = image.resize(new_size, Image.Resampling.LANCZOS)

            # Convert to Base64
            buffered = BytesIO()
            image.save(buffered, format="JPEG", quality=95)
            img_bytes = buffered.getvalue()
            img_base64 = base64.b64encode(img_bytes).decode('utf-8')

            print(f"DEBUG: Image converted to Base64: {len(img_base64)} chars")
            return img_base64

        except Exception as e:
            print(f"ERROR: Failed to convert file to Base64 image: {e}")
            import traceback
            traceback.print_exc()
            return None

    def extract_invoice_items_from_image(self, file_path: str) -> Optional[Dict]:
        """
        Extract invoice line items and totals from PDF/image using GPT-4o Vision

        Args:
            file_path: Path to PDF or image file

        Returns:
            Dict with structure:
            {
                "items": [
                    {
                        "item_name_raw": "部品名",
                        "amount_excl_tax": 1000,
                        "quantity": 1
                    },
                    ...
                ],
                "total_amount_excl_tax": 15000,  # AI-extracted total (tax excluded)
                "total_amount_incl_tax": 16500   # AI-extracted total (tax included)
            }
            Returns None if extraction fails
        """
        if not self.client:
            print("Azure OpenAI client not available")
            return None

        try:
            # Convert file to Base64 image
            image_base64 = self.convert_file_to_base64_image(file_path)
            if not image_base64:
                print("ERROR: Failed to convert file to Base64 image")
                return None

            # Construct the system prompt - simple and focused on visual analysis
            system_prompt = """
あなたは、自動車整備の見積書を視覚的に解析するプロフェッショナルAIです。
画像を見て、表形式の明細行と合計金額を読み取り、構造化データに変換してください。

# 抽出ルール
1. **視覚的な表構造の認識**:
   - 画像内の表（テーブル）を視覚的に認識してください
   - 各行は1つの明細アイテムを表します
   - 列: 品名、数量、単価、金額などを識別

2. **【重要】枠外の諸費用ボックスを必ず探す**:
   - **メインの明細表とは別に**、紙面の右上、右下、または欄外にある「諸費用」「法定費用」「代行料」と書かれた小さな表や枠を必ずスキャンしてください
   - これらの枠内にある項目（例：検査代行料、引取納車費用、自賠責保険、重量税、印紙代など）も、必ず `items` 配列に追加してください
   - **これらの項目を見落とすと、合計金額が合わなくなります**
   - 諸費用欄の特徴:
     - 通常、メインの明細表より小さい独立した表や枠線で囲まれている
     - 「諸費用」「法定費用」「その他費用」などの見出しがある
     - 金額が数千円～数万円の項目が複数並んでいる

3. **品名の抽出**:
   - 純粋な日本語の品名を抽出（記号、部品番号は除外）
   - 例: 「#バッテリー」→「バッテリー」
   - 例: 「76470-72M01 ワイパーラバー」→「ワイパーラバー」

4. **金額の抽出**:
   - 「金額」または「単価」列の数値を抽出
   - カンマ区切り（1,000）を数値化（1000）

5. **法定費用の分類**:
   - 「自賠責」「重量税」「印紙」「法定費用」「検査登録」という単語が含まれる項目は、非課税として分類してください
   - これらの項目は `cost_type` を `"statutory_fees"` としてください
   - 例: 「自賠責保険」→ `cost_type: "statutory_fees"`
   - 例: 「重量税」→ `cost_type: "statutory_fees"`
   - 例: 「印紙代」→ `cost_type: "statutory_fees"`

6. **集計行の除外**:
   - 明細表内の「小計」行は items に含めない

7. **業者住所の抽出**:
   - 見積書の発行元（工場・業者）の住所を `vendor_address` として抽出してください
   - **除外ルール**: 以下は請求先（自社）の住所なので抽出しないこと
     - 「東京都渋谷区神南1-19-4」
     - 「株式会社IDOM」の住所
   - 通常、見積書の上部または左上に記載されている発行元の住所を抽出
   - 住所が見つからない場合は null を返す

8. **【最重要】合計金額の厳格な分類**:
   見積書の最下部にある金額を正確に分類してください。以下の優先順位で判断すること。

   **A. `total_amount_incl_tax`（税込合計 = 最終支払金額）**:
   - これは **Grand Total（お客様が実際に支払う最終金額）** です
   - ラベル例: 「総合計」「合計（税込）」「お支払額」「Grand Total」
   - **見積書の一番下に大きく強調されている金額**
   - 消費税が既に含まれている最終的な数字
   - **もし金額が1つしか強調表示されていない場合、それは税込合計として扱う**

   **B. `total_amount_excl_tax`（税抜合計 = 小計）**:
   - これは **Subtotal（消費税や諸費用が加算される前の中間金額）** です
   - ラベル例: 「小計」「合計（税抜）」「対象額」「Subtotal」
   - **部品代 + 技術料の合計（消費税は含まない）**
   - Grand Totalより小さい金額
   - この金額に消費税を足すとGrand Totalになる

   **判断ルール**:
   1. 見積書に2つの合計金額がある場合:
      - 小さい方 → `total_amount_excl_tax`（税抜）
      - 大きい方 → `total_amount_incl_tax`（税込）
   2. 見積書に1つしか合計金額がない場合:
      - その金額 → `total_amount_incl_tax`（税込）
      - `total_amount_excl_tax` → null
   3. 「消費税」という行がある場合:
      - その直前の金額 → `total_amount_excl_tax`（税抜）
      - その直後の金額 → `total_amount_incl_tax`（税込）

9. **【厳守】合計金額の再計算禁止**:
   - 画像から読み取った総合計金額（`total_amount_incl_tax`）が、明細の合計と合わない場合でも、**画像に印字されている「総合計金額（Grand Total）」を最優先**して出力してください
   - **絶対に勝手に計算して数値を捏造しないこと**
   - 見積書に印刷されている金額こそが正しい公式金額です
   - 明細の合計と総合計が一致しない場合は、以下のいずれかの理由があります:
     - 枠外の諸費用項目を見落としている（必ず再スキャン）
     - 値引きや調整が加えられている
     - 端数処理による誤差
   - いずれの場合も、**画像に印刷されている総合計金額をそのまま出力**してください

10. **出力フォーマット**:
   {
     "vendor_address": "業者の住所" or null,
     "items": [
       {"item_name_raw": "品名", "amount_excl_tax": 数値, "quantity": 数値, "cost_type": "parts/labor/statutory_fees/other"}
     ],
     "total_amount_excl_tax": 数値 or null（税抜小計）,
     "total_amount_incl_tax": 数値（税込合計 = 最終支払金額）
   }

JSONのみを返してください。
"""

            user_prompt = """この見積書の画像を視覚的に解析してください。
以下の項目を読み取り、JSON形式で出力してください：
1. 業者の住所
2. **メインの明細表（品名、数量、金額）**
3. **【重要】右上や欄外にある「諸費用」「法定費用」の枠内の項目も必ず抽出してください**
4. フッターにある合計金額（税抜・税込）

※枠外の諸費用項目を見落とさないよう注意してください。これらの項目が漏れると合計金額が合わなくなります。"""

            print("=" * 80)
            print("DEBUG: Calling Azure OpenAI Vision API for invoice extraction...")
            print(f"DEBUG: Image Base64 length: {len(image_base64)} chars")
            print("=" * 80)

            # Call GPT-4o Vision API
            response = self.client.chat.completions.create(
                model=self.deployment,
                messages=[
                    {
                        "role": "system",
                        "content": system_prompt
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": user_prompt
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/jpeg;base64,{image_base64}"
                                }
                            }
                        ]
                    }
                ],
                temperature=0.3,
                max_tokens=2000,
                response_format={"type": "json_object"}
            )

            # Extract response
            content = response.choices[0].message.content
            print(f"DEBUG: Vision API response: {content[:500]}...")

            # Parse JSON
            try:
                result = json.loads(content)
                vendor_address = result.get('vendor_address')
                items = result.get('items', [])
                total_excl_tax = result.get('total_amount_excl_tax')
                total_incl_tax = result.get('total_amount_incl_tax')

                print(f"DEBUG: Vision API extracted vendor_address: {vendor_address}")
                print(f"DEBUG: Vision API extracted {len(items)} items")
                print(f"DEBUG: AI-extracted total (excl tax): {total_excl_tax}")
                print(f"DEBUG: AI-extracted total (incl tax): {total_incl_tax}")

                return {
                    'vendor_address': vendor_address,
                    'items': items,
                    'total_amount_excl_tax': total_excl_tax,
                    'total_amount_incl_tax': total_incl_tax
                }
            except json.JSONDecodeError as e:
                print(f"ERROR: Failed to parse Vision API JSON response: {e}")
                print(f"Response was: {content}")
                return None

        except Exception as e:
            print(f"ERROR: Azure OpenAI Vision API call failed: {e}")
            import traceback
            traceback.print_exc()
            return None

    # Legacy method for backward compatibility
    def extract_invoice_items(self, ocr_text: str) -> Optional[List[Dict]]:
        """
        Legacy method for text-based extraction (deprecated)
        Kept for backward compatibility
        """
        print("WARNING: extract_invoice_items (text-based) is deprecated. Use extract_invoice_items_from_image instead.")
        return None
