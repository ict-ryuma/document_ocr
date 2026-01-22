# frozen_string_literal: true

require "openai"

module Ocr
  # Primary OCR adapter using Azure OpenAI GPT-4o Vision API
  # Provides high-quality visual analysis of invoice/estimate documents
  class GptVisionAdapter < BaseAdapter
    SYSTEM_PROMPT = <<~PROMPT
      あなたは、自動車整備の見積書を視覚的に解析するプロフェッショナルAIです。
      画像を見て、表形式の明細行と合計金額を読み取り、構造化データに変換してください。

      # 抽出ルール
      1. **視覚的な表構造の認識**:
         - 画像内の表（テーブル）を視覚的に認識してください
         - 各行は1つの明細アイテムを表します
         - 列: 品名、数量、単価、金額などを識別

      2. **品名の抽出**:
         - 純粋な日本語の品名を抽出（記号、部品番号は除外）
         - 例: 「#バッテリー」→「バッテリー」
         - 例: 「76470-72M01 ワイパーラバー」→「ワイパーラバー」

      3. **金額の抽出**:
         - 「金額」または「単価」列の数値を抽出
         - カンマ区切り（1,000）を数値化（1000）

      4. **集計行の除外**:
         - 明細表内の「小計」行は items に含めない

      5. **業者住所の抽出**:
         - 見積書の発行元（工場・業者）の住所を `vendor_address` として抽出してください
         - **除外ルール**: 以下は請求先（自社）の住所なので抽出しないこと
           - 「東京都渋谷区神南1-19-4」
           - 「株式会社IDOM」の住所
         - 通常、見積書の上部または左上に記載されている発行元の住所を抽出
         - 住所が見つからない場合は null を返す

      6. **【最重要】合計金額の厳格な分類**:
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

      7. **出力フォーマット**:
         {
           "vendor_address": "業者の住所" or null,
           "items": [
             {"item_name_raw": "品名", "amount_excl_tax": 数値, "quantity": 数値}
           ],
           "total_amount_excl_tax": 数値 or null（税抜小計）,
           "total_amount_incl_tax": 数値（税込合計 = 最終支払金額）
         }

      JSONのみを返してください。
    PROMPT

    USER_PROMPT = "この見積書の画像を視覚的に解析してください。業者の住所、表形式の明細行（品名、数量、金額）、フッターにある合計金額（税抜・税込）を読み取り、JSON形式で出力してください。"

    def initialize
      @config = Rails.application.config.ocr.azure
      @timeout = Rails.application.config.ocr.timeouts[:vision_api]
      @client = build_client if available?
    end

    def extract(file_path)
      validate_file!(file_path)
      log_extraction_start(file_path)

      unless @client
        raise ConfigurationError, "Azure OpenAI client not configured"
      end

      # Convert file to base64 image
      converter = PdfConverterService.new
      image_base64 = converter.convert_to_base64(file_path)

      unless image_base64
        raise ExtractionError, "Failed to convert file to base64 image"
      end

      # Call Vision API
      result = call_vision_api(image_base64)

      log_extraction_success(result[:items]&.size || 0)
      result
    rescue Faraday::TimeoutError, Net::ReadTimeout => e
      log_extraction_failure(e)
      raise TimeoutError, "Vision API request timed out: #{e.message}"
    rescue StandardError => e
      log_extraction_failure(e)
      raise ExtractionError, "Vision API extraction failed: #{e.message}"
    end

    def available?
      @config[:api_key].present? && @config[:endpoint].present?
    end

    private

    def build_client
      base_url = @config[:endpoint].to_s.sub(%r{/$}, "")
      uri_base = "#{base_url}/openai/deployments/#{@config[:deployment_name]}"

      OpenAI::Client.new(
        access_token: @config[:api_key],
        uri_base: uri_base,
        api_type: :azure,
        api_version: @config[:api_version],
        request_timeout: @timeout
      )
    end

    def call_vision_api(image_base64)
      response = @client.chat(
        parameters: {
          model: @config[:deployment_name],
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            {
              role: "user",
              content: [
                { type: "text", text: USER_PROMPT },
                {
                  type: "image_url",
                  image_url: { url: "data:image/jpeg;base64,#{image_base64}" }
                }
              ]
            }
          ],
          temperature: 0.3,
          max_tokens: 2000,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      unless content
        raise ExtractionError, "Empty response from Vision API"
      end

      parse_vision_response(content)
    end

    def parse_vision_response(content)
      data = JSON.parse(content, symbolize_names: true)

      {
        vendor_address: data[:vendor_address],
        items: normalize_items(data[:items] || []),
        total_amount_excl_tax: data[:total_amount_excl_tax],
        total_amount_incl_tax: data[:total_amount_incl_tax]
      }
    rescue JSON::ParserError => e
      raise ExtractionError, "Failed to parse Vision API response: #{e.message}"
    end

    def normalize_items(items)
      items.map do |item|
        {
          item_name_raw: item[:item_name_raw].to_s,
          amount_excl_tax: item[:amount_excl_tax].to_i,
          quantity: (item[:quantity] || 1).to_i
        }
      end.reject { |item| item[:item_name_raw].blank? || item[:amount_excl_tax] <= 0 }
    end
  end
end
