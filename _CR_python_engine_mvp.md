Goal:
Rails から呼ばれる Python 解析エンジンの MVP を作成してください。
PDFパスを受け取り、OCRスタブ結果を解析して stdout に JSON を返します。

Scope:
- python_engine/main.py を作成
- OCR は未実装（スタブ）
- JSONスキーマを固定
- 状態を持たない

Acceptance Criteria:
- `python python_engine/main.py --pdf dummy.pdf` が stdout に JSON を出す
- JSONには以下を含める
  - vendor_name
  - estimate_date
  - total_excl_tax
  - total_incl_tax
  - items[]:
    - item_name_raw
    - item_name_norm
    - cost_type ("parts" | "labor")
    - amount_excl_tax
- "ワイパー" / "wiper" / "ブレード" は wiper_blade に正規化
- "工賃" を含む場合は labor、それ以外は parts
- Pythonは DB / kintone / ファイル保存を行わない

Output:
- {"files":[...]} 形式で必要なファイルのみ返す

Target files:
- python_engine/main.py
