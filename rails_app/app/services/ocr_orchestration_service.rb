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
    @document_ai_adapter = Ocr::DocumentAiAdapter.new
    @gpt_text_adapter = Ocr::GptTextAdapter.new
    @dummy_adapter = Ocr::DummyAdapter.new
  end

  # Extract and enhance data from PDF/image file using pipeline approach
  #
  # Pipeline:
  #   1. Document AI: 事実・構造を抽出
  #   2. GPT-4o Text: 意味補完・例外吸収
  #   3. Rails: 検証・人確認 (controller側で処理)
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
  # @raise [ExtractionFailedError] if Document AI extraction fails
  # @raise [EnhancementFailedError] if GPT-4o enhancement fails
  def extract(file_path, vendor_name: nil)
    # Stage 1: Document AI (事実・構造)
    raw_result = extract_with_document_ai(file_path)

    # Stage 2: GPT-4o Text (意味補完・例外吸収)
    enhanced_result = enhance_with_gpt(raw_result)

    # Build final response for Rails (検証・人確認)
    build_response(enhanced_result, vendor_name: vendor_name)
  end

  # Check which components are available
  #
  # @return [Hash] Availability status of each component
  def available_components
    {
      document_ai: @document_ai_adapter.available?,
      gpt_text: @gpt_text_adapter.available?,
      dummy: true
    }
  end

  private

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

  def build_response(enhanced_result, vendor_name: nil)
    items = enhanced_result[:items] || []

    # Apply normalization to items
    normalized_items = ProductNormalizerService.process_items(items)

    # Calculate totals if not provided
    total_excl_tax = calculate_total_excl_tax(enhanced_result, normalized_items)
    total_incl_tax = calculate_total_incl_tax(enhanced_result, total_excl_tax)

    {
      vendor_name: vendor_name.presence || enhanced_result[:vendor_name].presence || "Unknown Vendor",
      vendor_address: enhanced_result[:vendor_address],
      estimate_date: Date.current.to_s,
      total_excl_tax: total_excl_tax,
      total_incl_tax: total_incl_tax,
      items: normalized_items,
      validation_warnings: enhanced_result[:validation_warnings] || [],
      extraction_method: determine_extraction_method
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
end
