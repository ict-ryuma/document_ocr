# frozen_string_literal: true

require "openai"

module Ocr
  # GPT-4o Vision adapter - 最強プロンプト（最終決定版）
  class GptVisionAdapter < BaseAdapter
    # 🔥 最強プロンプト（シンプルイズベスト版）
    # 余計な思考プロセスを全廃し、視覚的な抽出のみに特化
    SYSTEM_PROMPT = <<~PROMPT
      あなたは画像内の文字を忠実に読み取るOCR AIです。
      以下のルールを【絶対厳守】してください。

      # 🚫 禁止事項
      1. **計算禁止**: 足し算、引き算、消費税の計算は一切禁止。
      2. **推測禁止**: 「たぶんこうだろう」という補正は禁止。
      3. **省略禁止**: 明細が何行あっても「以下省略」は禁止。

      # 👁️ 抽出ルール

      ## 1. 合計金額 (total_amount_incl_tax)
      - 画像内の以下のラベルを探す:
        「御見積金額」「概算御見積金額」「お支払い金額」「合計金額」「請求金額」
        「ご請求金額」「合計（税込）」「税込合計」「合計」「総合計」
        「Amount Due」「Total」「Total Amount」「Grand Total」「Balance Due」
      - その【真横】か【直下】にある数値を、そのまま抜き出す。
      - 例: ラベルの横に「133,934」があれば、明細の合計がいくらであろうと「133934」を出力する。
      - **管理番号（8桁以上でカンマなし）は無視する**
      - 「合計」が複数ある場合、最も大きい金額（税込と思われるもの）を選ぶ。

      ## 1-2. 税抜合計金額 (total_amount_excl_tax)
      - 画像内の以下のラベルを探す:
        「税抜合計」「合計（税抜）」「小計」「税抜金額」「税抜合計金額」
        「Subtotal」「Sub Total」「Net Amount」「Amount Before Tax」
      - その【真横】か【直下】にある数値を、そのまま抜き出す。
      - 例: ラベルの横に「124,030」があれば、明細の合計がいくらであろうと「124030」を出力する。
      - **見つからない場合のみnullを返す。絶対に計算で求めてはいけない。**

      ## 2. 業者名 (vendor_name)
      - 用紙の一番上にあるロゴや、最も大きな文字で書かれた会社名・屋号を抽出する。
      - 住所の近くにある会社名も候補とする。
      - 「株式会社」「有限会社」「合同会社」等の法人格だけでなく、その前後の社名も必ず含める。
        例: 「株式会社 ABC」であれば「株式会社ABC」ではなく「株式会社 ABC」全体を抽出する。
      - 英語の場合は「Company Name」「From」「Bill From」セクションの会社名を抽出する。
      - 絶対に「test」や「不明」で逃げないこと。

      ## 3. 明細行 (items)
      - 表の中身だけでなく、右側の「諸費用」「法定費用」枠も明細として扱う。
      - 品名は記号（#）や型番を含めて、印字通りに出力する。
      - 「重量税」「自賠責」「印紙」は必ず抽出する。
      - 金額が空欄の行は無視する。
      - **金額は「部品代」または「技術料」の列にある数値を優先的に読み取る。**

      ## 4. cost_type の分類
      - **statutory_fees**: 「自賠責」「重量税」「印紙」「法定」「検査登録」「リサイクル」を含む
      - **labor**: 「工賃」「作業」「技術料」「整備」「点検」を含む
      - **parts**: 「オイル」「バッテリー」「タイヤ」「ワイパー」「フィルター」「ブレーキ」を含む
      - **other**: 上記以外

      # 📤 出力形式
      JSONのみを出力してください。説明文、コメント、マークダウンブロックは一切不要です。
    PROMPT

    USER_PROMPT = <<~PROMPT
      この見積書画像を解析し、以下のJSON形式で出力してください。

      {
        "vendor_name": "会社名（画像上部の最も大きな文字）",
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
      @config = Rails.application.config.ocr.azure
      @timeout = Rails.application.config.ocr.timeouts[:vision_api]
      @client = build_client if available?
    end

    # Extract data from PDF/image file using GPT-4o Vision
    #
    # @param file_path [String] Path to PDF or image file
    # @return [Hash] Extracted data with structure defined in BaseAdapter
    # @raise [ExtractionError] if extraction fails
    # @raise [TimeoutError] if API call times out
    def extract(file_path)
      unless available?
        raise ConfigurationError, "Azure OpenAI Vision API is not configured"
      end

      Rails.logger.info "[GptVision] Starting extraction: #{File.basename(file_path)}"

      # Convert PDF to image if necessary
      image_path = ensure_image_format(file_path)

      # Analyze image with GPT-4o Vision
      raw_result = analyze_image(image_path)

      unless raw_result
        raise ExtractionError, "Failed to extract data from image"
      end

      # Normalize result to BaseAdapter format
      result = normalize_result(raw_result)

      Rails.logger.info "[GptVision] Extraction successful: #{result[:items]&.size || 0} items extracted"
      Rails.logger.info "[GptVision] Vendor: #{result[:vendor_name] || 'unknown'}"
      Rails.logger.info "[GptVision] Total (excl tax): #{result[:total_amount_excl_tax]}"
      Rails.logger.info "[GptVision] Total (incl tax): #{result[:total_amount_incl_tax]}"

      result
    rescue Timeout::Error => e
      Rails.logger.error "[GptVision] Timeout: #{e.message}"
      raise TimeoutError, "GPT Vision API timed out after #{@timeout}ms"
    rescue => e
      Rails.logger.error "[GptVision] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise ExtractionError, "GPT Vision extraction failed: #{e.message}"
    end

    def available?
      @config[:api_key].present? &&
        @config[:endpoint].present? &&
        @config[:deployment_name].present?
    end

    private

    def build_client
      # エンドポイントの末尾のスラッシュを除去
      base_url = @config[:endpoint].to_s.sub(%r{/$}, "")
      # Azure用パスの構築
      uri_base = "#{base_url}/openai/deployments/#{@config[:deployment_name]}"

      OpenAI::Client.new(
        access_token: @config[:api_key],
        uri_base: uri_base,
        api_type: :azure,
        api_version: @config[:api_version] || "2024-02-15-preview",
        request_timeout: 120  # 120 seconds hardcoded for safety (GPT-4o Vision requires more time)
      )
    end

    def analyze_image(image_path)
      Rails.logger.info "[GptVision] Starting analysis: #{File.basename(image_path)}"

      # Encode image to base64
      base64_image = encode_image(image_path)

      # Call GPT-4o Vision API
      # Note: For Azure OpenAI, model parameter is not needed as it's in the URI
      response = @client.chat(
        parameters: {
          messages: [
            { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: [
              { type: "text", text: USER_PROMPT },
              { type: "image_url", image_url: {
                url: "data:image/jpeg;base64,#{base64_image}",
                detail: "high"
              }}
            ]}
          ],
          temperature: 0,  # Deterministic output
          max_tokens: 10000,  # Allow for large item lists
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")

      unless content
        Rails.logger.error "[GptVision] Empty response from Azure OpenAI"
        return nil
      end

      # Log complete raw response for debugging
      Rails.logger.info "[GptVision] Raw response (FULL):"
      Rails.logger.info content

      # Log token usage for optimization
      usage = response.dig("usage")
      if usage
        Rails.logger.info "[GptVision] Token usage - Prompt: #{usage['prompt_tokens']}, Completion: #{usage['completion_tokens']}, Total: #{usage['total_tokens']}"
      end

      parse_json_response(content)
    end

    def encode_image(image_path)
      Base64.strict_encode64(File.read(image_path))
    end

    def parse_json_response(content)
      return nil unless content

      # Remove markdown code blocks if present
      json_str = content.gsub(/```json\n?/, '').gsub(/```\n?/, '').strip

      parsed = JSON.parse(json_str, symbolize_names: true)

      Rails.logger.info "[GptVision] Successfully parsed JSON with #{parsed[:items]&.size || 0} items"

      # Detailed validation logging
      if parsed[:items]&.empty?
        Rails.logger.warn "[GptVision] Warning: No items extracted from image"
      end

      if parsed[:vendor_name].blank?
        Rails.logger.warn "[GptVision] Warning: vendor_name not found"
      end

      # Log extracted totals for debugging
      Rails.logger.info "[GptVision] Extracted total_amount_excl_tax: #{parsed[:total_amount_excl_tax].inspect}"
      Rails.logger.info "[GptVision] Extracted total_amount_incl_tax: #{parsed[:total_amount_incl_tax].inspect}"

      if parsed[:total_amount_incl_tax].to_i == 0
        Rails.logger.warn "[GptVision] ⚠️  CRITICAL: total_amount_incl_tax is zero or missing!"
      end

      if parsed[:total_amount_excl_tax].to_i == 0
        Rails.logger.warn "[GptVision] ⚠️  CRITICAL: total_amount_excl_tax is zero or missing!"
      end

      parsed
    rescue JSON::ParserError => e
      Rails.logger.error "[GptVision] JSON parse error: #{e.message}"
      Rails.logger.error "[GptVision] Content was: #{content[0..1000]}"
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

    def ensure_image_format(file_path)
      # If already an image, return as-is
      return file_path if image_file?(file_path)

      # Convert PDF to image using ImageMagick
      require "mini_magick"

      output_path = File.join(Dir.tmpdir, "#{SecureRandom.hex(8)}.jpg")

      MiniMagick::Tool::Convert.new do |convert|
        convert.density(300)           # MUST come before input file for PDF rasterization
        convert << "#{file_path}[0]"  # First page only
        convert.quality(95)            # High quality
        convert.colorspace("RGB")
        convert.auto_orient            # Auto-rotate based on EXIF orientation
        convert.sharpen("0x1")         # Sharpen to enhance grid lines and column boundaries
        convert << output_path
      end

      output_path
    rescue => e
      Rails.logger.warn "[GptVision] PDF conversion failed: #{e.message}, using original file"
      file_path
    end

    def image_file?(file_path)
      extension = File.extname(file_path).downcase
      %w[.jpg .jpeg .png .gif .bmp].include?(extension)
    end
  end
end
