# frozen_string_literal: true

# OCR Orchestration Service
# Manages the 3-tier fallback strategy for PDF/image extraction:
#   1. GPT-4o Vision (Primary)
#   2. Document AI (Fallback)
#   3. Dummy (Development/Test)
class OcrOrchestrationService
  class AllAdaptersFailedError < StandardError; end

  # Japan consumption tax rate (10% as of 2019-10-01)
  CONSUMPTION_TAX_RATE = 0.10

  # Adapter chain in order of preference
  ADAPTER_CHAIN = [
    Ocr::GptVisionAdapter,
    Ocr::DocumentAiAdapter,
    Ocr::DummyAdapter
  ].freeze

  def initialize
    @adapters = build_adapter_chain
  end

  # Extract data from PDF/image file using available adapters
  #
  # @param file_path [String] Path to PDF or image file
  # @param vendor_name [String, nil] Override vendor name
  # @return [Hash] Extracted and normalized data with structure:
  #   {
  #     vendor_name: String,
  #     vendor_address: String or nil,
  #     estimate_date: String (YYYY-MM-DD),
  #     total_excl_tax: Integer,
  #     total_incl_tax: Integer,
  #     items: [{ item_name_raw:, item_name_norm:, cost_type:, amount_excl_tax:, quantity: }]
  #   }
  # @raise [AllAdaptersFailedError] if all adapters fail
  def extract(file_path, vendor_name: nil)
    errors = []

    @adapters.each do |adapter|
      next unless adapter.available?

      begin
        Rails.logger.info "[OcrOrchestration] Trying adapter: #{adapter.name}"

        raw_result = adapter.extract(file_path)
        return build_response(raw_result, vendor_name: vendor_name)
      rescue Ocr::BaseAdapter::ExtractionError,
             Ocr::BaseAdapter::TimeoutError,
             Ocr::BaseAdapter::ConfigurationError => e
        errors << { adapter: adapter.name, error: e.message }
        Rails.logger.warn "[OcrOrchestration] #{adapter.name} failed: #{e.message}"
        next
      end
    end

    # All adapters failed
    error_details = errors.map { |e| "#{e[:adapter]}: #{e[:error]}" }.join("; ")
    raise AllAdaptersFailedError, "All OCR adapters failed: #{error_details}"
  end

  # Check which adapters are available
  #
  # @return [Array<String>] Names of available adapters
  def available_adapters
    @adapters.select(&:available?).map(&:name)
  end

  private

  def build_adapter_chain
    ADAPTER_CHAIN.map(&:new)
  end

  def build_response(raw_result, vendor_name: nil)
    items = raw_result[:items] || []

    # Apply normalization to items
    normalized_items = ProductNormalizerService.process_items(items)

    # Calculate totals if not provided
    total_excl_tax = calculate_total_excl_tax(raw_result, normalized_items)
    total_incl_tax = calculate_total_incl_tax(raw_result, total_excl_tax)

    {
      vendor_name: vendor_name.presence || raw_result[:vendor_name].presence || "Unknown Vendor",
      vendor_address: raw_result[:vendor_address],
      estimate_date: Date.current.to_s,
      total_excl_tax: total_excl_tax,
      total_incl_tax: total_incl_tax,
      items: normalized_items
    }
  end

  def calculate_total_excl_tax(raw_result, items)
    # Use AI-extracted total if available
    if raw_result[:total_amount_excl_tax].present?
      return raw_result[:total_amount_excl_tax].to_i
    end

    # Fallback: sum of item amounts
    items.sum { |item| item[:amount_excl_tax].to_i }
  end

  def calculate_total_incl_tax(raw_result, total_excl_tax)
    # Use AI-extracted total if available
    if raw_result[:total_amount_incl_tax].present?
      return raw_result[:total_amount_incl_tax].to_i
    end

    # Fallback: apply consumption tax
    (total_excl_tax * (1 + CONSUMPTION_TAX_RATE)).to_i
  end
end
