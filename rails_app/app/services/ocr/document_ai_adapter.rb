# frozen_string_literal: true

require "google/cloud/document_ai/v1"
require "openai"

module Ocr
  # Google Document AI + GPT-4o Vision Hybrid Adapter
  #
  # Strategy:
  #   1. Document AI: Extract raw text/table structure (high precision for structure)
  #   2. GPT-4o: Semantic understanding and JSON formatting (high precision for meaning)
  #
  # This hybrid approach leverages the strengths of both:
  #   - Document AI: Superior at detecting tables, columns, and physical layout
  #   - GPT-4o: Superior at semantic understanding and contextual classification
  class DocumentAiAdapter < BaseAdapter
    # GPT-4o prompt for semantic processing of Document AI extracted text
    SYSTEM_PROMPT = <<~PROMPT
      あなたはGoogle Document AIが抽出したテキストを解析し、見積書のJSON形式に変換するAIです。
      以下のルールを【絶対厳守】してください。

      # 🚫 禁止事項
      1. **計算禁止**: 足し算、引き算、消費税の計算は一切禁止。
      2. **推測禁止**: テキストに書かれていないことは推測しない。
      3. **省略禁止**: 明細が何行あっても「以下省略」は禁止。

      # 👁️ 抽出ルール

      ## 1. 合計金額 (total_amount_incl_tax)
      - 「御見積金額」「概算御見積金額」「お支払い金額」というラベルを探す。
      - その真横か直下にある数値を、そのまま抜き出す。
      - 管理番号（8桁以上でカンマなし）は無視する。

      ## 1-2. 税抜合計金額 (total_amount_excl_tax)
      - 「税抜合計」「合計（税抜）」「小計」「税抜金額」というラベルを探す。
      - その真横か直下にある数値を、そのまま抜き出す。
      - 例: ラベルの横に「124,030」があれば「124030」を出力する。
      - **見つからない場合のみnullを返す。絶対に計算で求めてはいけない。**

      ## 2. 業者名 (vendor_name)
      - テキストの最初の方にある会社名を抽出する。
      - 「株式会社」「有限会社」などの法人格を含める。
      - 絶対に「test」や「不明」で逃げないこと。

      ## 3. 明細行 (items)
      - Document AIが抽出した表の各行を明細として扱う。
      - 品名は記号（#）や型番を含めて、印字通りに出力する。
      - 「重量税」「自賠責」「印紙」は必ず抽出する。
      - 金額が空欄の行は無視する。
      - **2列構成の場合**: 「部品代」と「技術料」が別列にある場合、どちらか一方のみを抽出する（両方を別項目にしない）。

      ## 4. cost_type の分類
      - **statutory_fees**: 「自賠責」「重量税」「印紙」「法定」「検査登録」「リサイクル」を含む
      - **labor**: 「工賃」「作業」「技術料」「整備」「点検」を含む
      - **parts**: 「オイル」「バッテリー」「タイヤ」「ワイパー」「フィルター」「ブレーキ」を含む
      - **other**: 上記以外

      # 📤 出力形式
      JSONのみを出力してください。説明文、コメント、マークダウンブロックは一切不要です。
    PROMPT

    USER_PROMPT_TEMPLATE = <<~PROMPT
      以下はGoogle Document AIが抽出したテキストです。このテキストから見積書情報を抽出し、以下のJSON形式で出力してください。

      【抽出されたテキスト】
      %{extracted_text}

      【出力形式】
      {
        "vendor_name": "会社名（テキスト冒頭の最も大きな文字）",
        "vendor_address": "住所",
        "estimate_date": "YYYY-MM-DD",
        "total_amount_incl_tax": 数値（「御見積金額」ラベルの真横の数値、計算禁止）,
        "total_amount_excl_tax": 数値（「税抜合計」の数値、なければnull）,
        "items": [
          {
            "item_name_raw": "品名（印字通り、記号・型番含む）",
            "quantity": 数値,
            "amount_excl_tax": 数値,
            "cost_type": "statutory_fees|labor|parts|other"
          }
        ]
      }

      JSONのみを出力してください。
    PROMPT

    def initialize
      @config = Rails.application.config.ocr.document_ai
      @timeout = Rails.application.config.ocr.timeouts[:document_ai]
      @gpt_client = build_gpt_client if available?
    end

    # Extract data from PDF file using Document AI + GPT-4o hybrid approach
    #
    # @param file_path [String] Path to PDF file
    # @return [Hash] Extracted data with structure defined in BaseAdapter
    # @raise [ExtractionError] if extraction fails
    # @raise [TimeoutError] if API call times out
    def extract(file_path)
      unless available?
        raise ConfigurationError, "Document AI or Azure OpenAI is not configured"
      end

      Rails.logger.info "[DocumentAI] Starting hybrid extraction: #{File.basename(file_path)}"

      # Step 1: Extract text/table structure using Document AI
      extracted_text = extract_with_document_ai(file_path)

      unless extracted_text.present?
        raise ExtractionError, "Failed to extract text from Document AI"
      end

      Rails.logger.info "[DocumentAI] Extracted #{extracted_text.length} characters from Document AI"

      # Step 2: Process with GPT-4o for semantic understanding
      raw_result = process_with_gpt(extracted_text)

      unless raw_result
        raise ExtractionError, "Failed to process text with GPT-4o"
      end

      # Normalize result to BaseAdapter format
      result = normalize_result(raw_result)

      Rails.logger.info "[DocumentAI] Extraction successful: #{result[:items]&.size || 0} items extracted"
      Rails.logger.info "[DocumentAI] Vendor: #{result[:vendor_name] || 'unknown'}"
      Rails.logger.info "[DocumentAI] Total (excl tax): #{result[:total_amount_excl_tax]}"
      Rails.logger.info "[DocumentAI] Total (incl tax): #{result[:total_amount_incl_tax]}"

      result
    rescue Timeout::Error => e
      Rails.logger.error "[DocumentAI] Timeout: #{e.message}"
      raise TimeoutError, "Document AI API timed out after #{@timeout}ms"
    rescue => e
      Rails.logger.error "[DocumentAI] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise ExtractionError, "Document AI extraction failed: #{e.message}"
    end

    def available?
      # Check Document AI configuration
      document_ai_configured = @config[:project_id].present? &&
                               @config[:processor_id].present? &&
                               @config[:location].present?

      # Check Azure OpenAI configuration
      azure_config = Rails.application.config.ocr.azure
      gpt_configured = azure_config[:api_key].present? &&
                       azure_config[:endpoint].present? &&
                       azure_config[:deployment_name].present?

      document_ai_configured && gpt_configured
    end

    private

    def build_gpt_client
      azure_config = Rails.application.config.ocr.azure
      base_url = azure_config[:endpoint].to_s.sub(%r{/$}, "")
      uri_base = "#{base_url}/openai/deployments/#{azure_config[:deployment_name]}"

      OpenAI::Client.new(
        access_token: azure_config[:api_key],
        uri_base: uri_base,
        api_type: :azure,
        api_version: azure_config[:api_version] || "2024-02-15-preview",
        request_timeout: 120
      )
    end

    def extract_with_document_ai(file_path)
      Rails.logger.info "[DocumentAI] Calling Document AI API..."

      # Read PDF file
      content = File.binread(file_path)

      # Create Document AI client
      client = Google::Cloud::DocumentAI::V1::DocumentProcessorService::Client.new do |config|
        config.credentials = @config[:credentials_path]
      end

      # Build processor resource name
      processor_name = client.processor_path(
        project: @config[:project_id],
        location: @config[:location],
        processor: @config[:processor_id]
      )

      # Create process request
      request = Google::Cloud::DocumentAI::V1::ProcessRequest.new(
        name: processor_name,
        raw_document: {
          content: content,
          mime_type: "application/pdf"
        }
      )

      # Process document
      response = client.process_document(request)
      document = response.document

      # Extract text with layout information
      extracted_text = document.text

      # Log table detection if available
      if document.pages&.any?
        document.pages.each_with_index do |page, page_idx|
          if page.tables&.any?
            Rails.logger.info "[DocumentAI] Page #{page_idx + 1}: Detected #{page.tables.size} tables"

            page.tables.each_with_index do |table, table_idx|
              Rails.logger.info "[DocumentAI] Table #{table_idx + 1}: #{table.header_rows&.size || 0} header rows, #{table.body_rows&.size || 0} body rows"
            end
          end
        end
      end

      extracted_text
    rescue => e
      Rails.logger.error "[DocumentAI] Document AI API error: #{e.message}"
      raise ExtractionError, "Document AI failed: #{e.message}"
    end

    def process_with_gpt(extracted_text)
      Rails.logger.info "[DocumentAI] Processing with GPT-4o..."

      # Truncate text if too long (to avoid token limits)
      truncated_text = extracted_text[0..20000]  # ~20K characters ≈ 5K tokens

      user_prompt = USER_PROMPT_TEMPLATE % { extracted_text: truncated_text }

      response = @gpt_client.chat(
        parameters: {
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: user_prompt }
          ],
          temperature: 0,
          max_tokens: 10000,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")

      unless content
        Rails.logger.error "[DocumentAI] Empty response from GPT-4o"
        return nil
      end

      # Log complete raw response for debugging
      Rails.logger.info "[DocumentAI] GPT-4o raw response:"
      Rails.logger.info content

      # Log token usage
      usage = response.dig("usage")
      if usage
        Rails.logger.info "[DocumentAI] Token usage - Prompt: #{usage['prompt_tokens']}, Completion: #{usage['completion_tokens']}, Total: #{usage['total_tokens']}"
      end

      parse_json_response(content)
    end

    def parse_json_response(content)
      return nil unless content

      # Remove markdown code blocks if present
      json_str = content.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip

      parsed = JSON.parse(json_str, symbolize_names: true)

      Rails.logger.info "[DocumentAI] Successfully parsed JSON with #{parsed[:items]&.size || 0} items"

      # Validation logging
      if parsed[:items]&.empty?
        Rails.logger.warn "[DocumentAI] Warning: No items extracted"
      end

      if parsed[:vendor_name].blank?
        Rails.logger.warn "[DocumentAI] Warning: vendor_name not found"
      end

      Rails.logger.info "[DocumentAI] Extracted total_amount_excl_tax: #{parsed[:total_amount_excl_tax].inspect}"
      Rails.logger.info "[DocumentAI] Extracted total_amount_incl_tax: #{parsed[:total_amount_incl_tax].inspect}"

      if parsed[:total_amount_incl_tax].to_i == 0
        Rails.logger.warn "[DocumentAI] ⚠️  CRITICAL: total_amount_incl_tax is zero or missing!"
      end

      if parsed[:total_amount_excl_tax].to_i == 0
        Rails.logger.warn "[DocumentAI] ⚠️  CRITICAL: total_amount_excl_tax is zero or missing!"
      end

      parsed
    rescue JSON::ParserError => e
      Rails.logger.error "[DocumentAI] JSON parse error: #{e.message}"
      Rails.logger.error "[DocumentAI] Content was: #{content[0..1000]}"
      nil
    end

    def normalize_result(raw_result)
      items = (raw_result[:items] || []).map do |item|
        {
          item_name_raw: item[:item_name_raw].to_s,
          item_name_corrected: nil,  # Will be normalized by ProductNormalizerService
          amount_excl_tax: item[:amount_excl_tax].to_i,
          quantity: (item[:quantity] || 1).to_i,
          cost_type: item[:cost_type] || "unknown",
          confidence: "high"
        }
      end.reject { |item| item[:item_name_raw].blank? || item[:amount_excl_tax] <= 0 }

      {
        vendor_name: raw_result[:vendor_name],
        vendor_address: raw_result[:vendor_address],
        estimate_date: raw_result[:estimate_date],
        items: items,
        total_amount_excl_tax: raw_result[:total_amount_excl_tax],
        total_amount_incl_tax: raw_result[:total_amount_incl_tax],
        validation_warnings: []
      }
    end
  end
end
