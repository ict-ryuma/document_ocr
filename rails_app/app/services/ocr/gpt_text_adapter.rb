# frozen_string_literal: true

require "openai"

module Ocr
  # GPT-4o Text adapter for semantic completion and exception handling
  # Takes structured data from Document AI and enhances it with AI understanding
  class GptTextAdapter < BaseAdapter
    SYSTEM_PROMPT = <<~PROMPT
      あなたは、自動車整備の見積書データを意味補完・例外吸収するプロフェッショナルAIです。
      Document AIから抽出された構造化データを受け取り、以下の処理を行ってください。

      # 処理ルール

      1. **品名の正規化・補完**:
         - OCRの誤認識を修正（例: 「ワイパ一」→「ワイパー」）
         - 略称を正式名称に補完（例: 「E/G OIL」→「エンジンオイル」）
         - 部品番号や記号を除去し、純粋な品名を抽出
         - 例: 「76470-72M01 ワイパーラバー」→「ワイパーラバー」

      2. **金額の検証・補正**:
         - 明らかな桁ずれを検出し修正（例: 38000→3800）
         - カンマ区切りの誤認識を修正
         - 税込・税抜の判定ミスを修正

      3. **欠損データの推測補完**:
         - 数量が欠けている場合は1と推測
         - 金額が欠けている明細は除外をマーク
         - 業者名が欠けている場合は文脈から推測

      4. **例外パターンの吸収**:
         - 「工賃込み」表記の分離処理
         - セット価格の処理
         - 割引・値引きの適切な処理

      5. **合計金額の整合性確認**:
         - 明細合計と記載合計の差異を検出
         - 消費税計算の検証（10%）
         - 不整合がある場合は警告フラグを付与

      6. **出力フォーマット**:
         入力されたJSONを補完・修正して返却してください。
         {
           "vendor_name": "業者名（補完後）",
           "vendor_address": "業者住所（補完後）",
           "items": [
             {
               "item_name_raw": "元の品名",
               "item_name_corrected": "修正後の品名",
               "amount_excl_tax": 数値,
               "quantity": 数値,
               "confidence": "high" | "medium" | "low",
               "correction_notes": "修正内容のメモ（任意）"
             }
           ],
           "total_amount_excl_tax": 数値,
           "total_amount_incl_tax": 数値,
           "validation_warnings": ["警告メッセージ配列"],
           "processing_notes": "処理に関するメモ"
         }

      JSONのみを返してください。
    PROMPT

    def initialize
      @config = Rails.application.config.ocr.azure
      @timeout = Rails.application.config.ocr.timeouts[:vision_api]
      @client = build_client if available?
    end

    # Enhance Document AI results with semantic understanding
    #
    # @param document_ai_result [Hash] Raw extraction from Document AI
    # @return [Hash] Enhanced and validated data
    def enhance(document_ai_result)
      unless @client
        raise ConfigurationError, "Azure OpenAI client not configured"
      end

      Rails.logger.info "[GptText] Starting semantic enhancement"

      result = call_text_api(document_ai_result)

      Rails.logger.info "[GptText] Enhancement complete: #{result[:items]&.size || 0} items"
      result
    rescue Faraday::TimeoutError, Net::ReadTimeout => e
      Rails.logger.warn "[GptText] API timeout: #{e.message}"
      raise TimeoutError, "GPT Text API request timed out: #{e.message}"
    rescue StandardError => e
      Rails.logger.warn "[GptText] Enhancement failed: #{e.message}"
      raise ExtractionError, "GPT Text enhancement failed: #{e.message}"
    end

    # For compatibility with adapter interface
    def extract(file_path)
      raise NotImplementedError, "GptTextAdapter.enhance() should be used instead of extract()"
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

    def call_text_api(document_ai_result)
      user_prompt = <<~PROMPT
        以下のDocument AI抽出結果を意味補完・例外吸収してください：

        ```json
        #{document_ai_result.to_json}
        ```
      PROMPT

      response = @client.chat(
        parameters: {
          model: @config[:deployment_name],
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: user_prompt }
          ],
          temperature: 0.2,
          max_tokens: 3000,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      unless content
        raise ExtractionError, "Empty response from GPT Text API"
      end

      parse_response(content, document_ai_result)
    end

    def parse_response(content, original_result)
      data = JSON.parse(content, symbolize_names: true)

      {
        vendor_name: data[:vendor_name],
        vendor_address: data[:vendor_address],
        items: normalize_enhanced_items(data[:items] || [], original_result[:items] || []),
        total_amount_excl_tax: data[:total_amount_excl_tax],
        total_amount_incl_tax: data[:total_amount_incl_tax],
        validation_warnings: data[:validation_warnings] || [],
        processing_notes: data[:processing_notes]
      }
    rescue JSON::ParserError => e
      raise ExtractionError, "Failed to parse GPT Text response: #{e.message}"
    end

    def normalize_enhanced_items(enhanced_items, original_items)
      enhanced_items.map.with_index do |item, idx|
        original = original_items[idx] || {}

        {
          item_name_raw: item[:item_name_raw] || original[:item_name_raw].to_s,
          item_name_corrected: item[:item_name_corrected],
          amount_excl_tax: item[:amount_excl_tax].to_i,
          quantity: (item[:quantity] || 1).to_i,
          confidence: item[:confidence] || "medium",
          correction_notes: item[:correction_notes]
        }
      end.reject { |item| item[:item_name_raw].blank? || item[:amount_excl_tax] <= 0 }
    end
  end
end
