# frozen_string_literal: true

# OCR Orchestration Service
# Manages the 2-stage pipeline for PDF/image extraction:
#   Stage 1: Document AI (事実・構造抽出)
#   Stage 2: GPT-4o Text (意味補完・例外吸収)
#   Stage 3: Rails (検証・人確認) - handled in controller
class OcrOrchestrationService
  class ExtractionFailedError < StandardError; end
  class EnhancementFailedError < StandardError; end

  # Japan consumption tax rate (10% as of 2019-10-01)
  CONSUMPTION_TAX_RATE = 0.10

  def initialize
    @gpt_vision_adapter = Ocr::GptVisionAdapter.new
    @document_ai_adapter = Ocr::DocumentAiAdapter.new
    @gpt_text_adapter = Ocr::GptTextAdapter.new
    @dummy_adapter = Ocr::DummyAdapter.new
  end

  # Extract and enhance data from PDF/image file using hybrid merge strategy
  #
  # Merge Strategy:
  #   1. Execute both Document AI Hybrid AND GPT-4o Vision in parallel (or sequentially)
  #   2. Merge results with "best of both" approach:
  #      - Header info (vendor_name, total_amount, date): from GPT-4o Vision
  #      - Body info (items): from Document AI Hybrid
  #   3. Fallback to single adapter if one fails
  #
  # @param file_path [String] Path to PDF or image file
  # @param vendor_name [String, nil] Override vendor name
  # @return [Hash] Extracted and enhanced data with structure:
  #   {
  #     vendor_name: String,
  #     vendor_address: String or nil,
  #     estimate_date: String (YYYY-MM-DD),
  #     total_excl_tax: Integer,
  #     total_incl_tax: Integer,
  #     items: [{ item_name_raw:, item_name_norm:, cost_type:, amount_excl_tax:, quantity: }],
  #     validation_warnings: Array,
  #     extraction_method: String
  #   }
  # @raise [ExtractionFailedError] if all extraction methods fail
  def extract(file_path, vendor_name: nil)
    document_ai_result = nil
    gpt_vision_result = nil

    # Try Document AI Hybrid (for detailed items extraction)
    if @document_ai_adapter.available?
      begin
        Rails.logger.info "[OcrOrchestration] Executing Document AI Hybrid for items extraction"
        document_ai_result = @document_ai_adapter.extract(file_path)
        Rails.logger.info "[OcrOrchestration] Document AI extracted #{document_ai_result[:items]&.size || 0} items"
      rescue Ocr::BaseAdapter::ExtractionError,
             Ocr::BaseAdapter::TimeoutError,
             Ocr::BaseAdapter::ConfigurationError => e
        Rails.logger.warn "[OcrOrchestration] Document AI Hybrid failed: #{e.message}"
      end
    end

    # Try GPT-4o Vision (for header info extraction)
    if @gpt_vision_adapter.available?
      begin
        Rails.logger.info "[OcrOrchestration] Executing GPT-4o Vision for header extraction"
        gpt_vision_result = extract_with_gpt_vision(file_path)
        Rails.logger.info "[OcrOrchestration] GPT Vision extracted header info"
      rescue Ocr::BaseAdapter::ExtractionError,
             Ocr::BaseAdapter::TimeoutError,
             Ocr::BaseAdapter::ConfigurationError => e
        Rails.logger.warn "[OcrOrchestration] GPT Vision failed: #{e.message}"
      end
    end

    # Merge results with "best of both" strategy
    if document_ai_result && gpt_vision_result
      Rails.logger.info "[OcrOrchestration] Merging results: Header from GPT Vision + Items from Document AI"
      merged_result = merge_results(gpt_vision_result, document_ai_result)
      return build_response(merged_result, vendor_name: vendor_name, method: "Hybrid Merge (Vision Header + DocumentAI Items)")
    elsif document_ai_result
      Rails.logger.info "[OcrOrchestration] Using Document AI only (GPT Vision failed)"
      return build_response(document_ai_result, vendor_name: vendor_name, method: "Document AI Hybrid (solo)")
    elsif gpt_vision_result
      Rails.logger.info "[OcrOrchestration] Using GPT Vision only (Document AI failed)"
      return build_response(gpt_vision_result, vendor_name: vendor_name, method: "GPT-4o Vision (solo)")
    end

    # Fallback to dummy for development
    if Rails.env.development? || Rails.env.test?
      Rails.logger.info "[OcrOrchestration] Using Dummy adapter (all extractors failed)"
      result = @dummy_adapter.extract(file_path)
      return build_response(result, vendor_name: vendor_name, method: "Dummy (development)")
    end

    raise ExtractionFailedError, "All extraction methods failed or unavailable"
  end

  # Check which components are available
  #
  # @return [Hash] Availability status of each component
  def available_components
    {
      document_ai_hybrid: @document_ai_adapter.available?,
      gpt_vision: @gpt_vision_adapter.available?,
      gpt_text: @gpt_text_adapter.available?,
      dummy: true
    }
  end

  private

  # Merge results from GPT Vision (header) and Document AI (items)
  #
  # @param vision_result [Hash] GPT-4o Vision extraction result (good at header info)
  # @param docai_result [Hash] Document AI extraction result (good at items)
  # @return [Hash] Merged result with best of both
  def merge_results(vision_result, docai_result)
    Rails.logger.info "[OcrOrchestration] Merging: Vision header (#{vision_result[:vendor_name]}, ¥#{vision_result[:total_amount_incl_tax]}) + DocumentAI items (#{docai_result[:items]&.size || 0} items)"

    {
      # Header info: from GPT-4o Vision (more accurate for large fonts and labels)
      vendor_name: vision_result[:vendor_name],
      vendor_address: vision_result[:vendor_address],
      estimate_date: vision_result[:estimate_date],
      total_amount_excl_tax: vision_result[:total_amount_excl_tax],
      total_amount_incl_tax: vision_result[:total_amount_incl_tax],

      # Body info: from Document AI (more accurate for table structure)
      items: docai_result[:items] || [],

      # Merge validation warnings
      validation_warnings: (vision_result[:validation_warnings] || []) + (docai_result[:validation_warnings] || [])
    }
  end

  def extract_with_gpt_vision(file_path)
    Rails.logger.info "[OcrOrchestration] Using GPT-4o Vision (direct image analysis)"
    begin
      result = @gpt_vision_adapter.extract(file_path)
      Rails.logger.info "[OcrOrchestration] Vision extraction complete: #{result[:items]&.size || 0} items"
      result
    rescue Ocr::BaseAdapter::ExtractionError,
           Ocr::BaseAdapter::TimeoutError,
           Ocr::BaseAdapter::ConfigurationError => e
      Rails.logger.warn "[OcrOrchestration] GPT Vision failed: #{e.message}"
      raise ExtractionFailedError, "GPT Vision extraction failed: #{e.message}"
    end
  end

  def extract_with_document_ai(file_path)
    if @document_ai_adapter.available?
      Rails.logger.info "[OcrOrchestration] Stage 1: Document AI extraction"
      begin
        @document_ai_adapter.extract(file_path)
      rescue Ocr::BaseAdapter::ExtractionError,
             Ocr::BaseAdapter::TimeoutError,
             Ocr::BaseAdapter::ConfigurationError => e
        Rails.logger.warn "[OcrOrchestration] Document AI failed: #{e.message}"
        # Fallback to dummy for development
        if Rails.env.development? || Rails.env.test?
          Rails.logger.info "[OcrOrchestration] Falling back to Dummy adapter"
          @dummy_adapter.extract(file_path)
        else
          raise ExtractionFailedError, "Document AI extraction failed: #{e.message}"
        end
      end
    elsif Rails.env.development? || Rails.env.test?
      Rails.logger.info "[OcrOrchestration] Stage 1: Using Dummy adapter (Document AI not available)"
      @dummy_adapter.extract(file_path)
    else
      raise ExtractionFailedError, "Document AI is not configured"
    end
  end

  def enhance_with_gpt(raw_result)
    if @gpt_text_adapter.available?
      Rails.logger.info "[OcrOrchestration] Stage 2: GPT-4o Text enhancement"
      begin
        @gpt_text_adapter.enhance(raw_result)
      rescue Ocr::BaseAdapter::ExtractionError,
             Ocr::BaseAdapter::TimeoutError,
             Ocr::BaseAdapter::ConfigurationError => e
        Rails.logger.warn "[OcrOrchestration] GPT enhancement failed: #{e.message}, using raw result"
        # Continue with raw result if GPT fails
        raw_result.merge(validation_warnings: [ "GPT enhancement skipped: #{e.message}" ])
      end
    else
      Rails.logger.info "[OcrOrchestration] Stage 2: Skipping GPT enhancement (not configured)"
      raw_result.merge(validation_warnings: [ "GPT enhancement not available" ])
    end
  end

  def build_response(enhanced_result, vendor_name: nil, method: nil)
    items = enhanced_result[:items] || []

    # Apply normalization to items
    normalized_items = ProductNormalizerService.process_items(items)

    # Calculate totals if not provided
    total_excl_tax = calculate_total_excl_tax(enhanced_result, normalized_items)
    total_incl_tax = calculate_total_incl_tax(enhanced_result, total_excl_tax)

    # Parse and convert Japanese date (Reiwa) to ISO8601 format
    estimate_date = parse_japanese_date(enhanced_result[:estimate_date])

    {
      vendor_name: vendor_name.presence || enhanced_result[:vendor_name].presence || "Unknown Vendor",
      vendor_address: enhanced_result[:vendor_address],
      estimate_date: estimate_date,
      total_excl_tax: total_excl_tax,
      total_incl_tax: total_incl_tax,
      items: normalized_items,
      validation_warnings: enhanced_result[:validation_warnings] || [],
      extraction_method: method || determine_extraction_method
    }
  end

  def calculate_total_excl_tax(result, items)
    # Use AI-extracted total if available
    if result[:total_amount_excl_tax].present?
      return result[:total_amount_excl_tax].to_i
    end

    # Fallback: sum of item amounts
    items.sum { |item| item[:amount_excl_tax].to_i }
  end

  def calculate_total_incl_tax(result, total_excl_tax)
    # Use AI-extracted total if available
    if result[:total_amount_incl_tax].present?
      return result[:total_amount_incl_tax].to_i
    end

    # Fallback: apply consumption tax
    (total_excl_tax * (1 + CONSUMPTION_TAX_RATE)).to_i
  end

  def determine_extraction_method
    methods = []
    methods << "DocumentAI" if @document_ai_adapter.available?
    methods << "Dummy" if methods.empty? && (Rails.env.development? || Rails.env.test?)
    methods << "GPT-4o" if @gpt_text_adapter.available?
    methods.join(" → ")
  end

  # Parse Japanese date (Reiwa era) and convert to ISO8601 format (YYYY-MM-DD)
  #
  # Examples:
  #   "令和7年07月21日" => "2025-07-21"
  #   "令和1年5月1日"   => "2019-05-01"
  #   "2025-07-21"      => "2025-07-21" (already ISO8601)
  #   nil               => Date.current.to_s
  #
  # @param date_str [String, nil] Date string in Japanese or ISO8601 format
  # @return [String] Date in ISO8601 format (YYYY-MM-DD)
  def parse_japanese_date(date_str)
    return Date.current.to_s unless date_str.present?

    # Already in ISO8601 format? Return as-is
    return date_str if date_str.match?(/^\d{4}-\d{2}-\d{2}$/)

    # Parse Reiwa era (令和XX年XX月XX日)
    if match = date_str.match(/令和(\d+)年(\d+)月(\d+)日/)
      reiwa_year = match[1].to_i
      month = match[2].to_i
      day = match[3].to_i

      # Reiwa 1 = 2019 (started May 1, 2019)
      western_year = 2018 + reiwa_year

      # Format as ISO8601 (YYYY-MM-DD)
      formatted_date = "%04d-%02d-%02d" % [ western_year, month, day ]

      Rails.logger.info "[OcrOrchestration] Converted Japanese date: #{date_str} => #{formatted_date}"
      return formatted_date
    end

    # Parse Heisei era (平成XX年XX月XX日) - for older documents
    if match = date_str.match(/平成(\d+)年(\d+)月(\d+)日/)
      heisei_year = match[1].to_i
      month = match[2].to_i
      day = match[3].to_i

      # Heisei 1 = 1989
      western_year = 1988 + heisei_year

      formatted_date = "%04d-%02d-%02d" % [ western_year, month, day ]

      Rails.logger.info "[OcrOrchestration] Converted Japanese date: #{date_str} => #{formatted_date}"
      return formatted_date
    end

    # Could not parse, use current date as fallback
    Rails.logger.warn "[OcrOrchestration] Could not parse date: #{date_str}, using current date"
    Date.current.to_s
  rescue => e
    Rails.logger.error "[OcrOrchestration] Date parsing error: #{e.message}"
    Date.current.to_s
  end
end
