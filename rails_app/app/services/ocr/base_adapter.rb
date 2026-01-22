# frozen_string_literal: true

module Ocr
  # Base class for OCR adapters
  # All OCR adapters MUST implement:
  #   - extract(file_path) -> Hash
  #   - available? -> Boolean
  class BaseAdapter
    # Custom exceptions
    class ExtractionError < StandardError; end
    class TimeoutError < StandardError; end
    class ConfigurationError < StandardError; end

    # Extract data from PDF/image file
    #
    # @param file_path [String] Path to PDF or image file
    # @return [Hash] Extracted data with structure:
    #   {
    #     vendor_address: String or nil,
    #     items: [{ item_name_raw: String, amount_excl_tax: Integer, quantity: Integer }],
    #     total_amount_excl_tax: Integer or nil,
    #     total_amount_incl_tax: Integer
    #   }
    # @raise [ExtractionError] if extraction fails
    # @raise [TimeoutError] if request times out
    def extract(file_path)
      raise NotImplementedError, "#{self.class}#extract must be implemented"
    end

    # Check if this adapter is properly configured and available
    #
    # @return [Boolean] true if adapter can be used
    def available?
      raise NotImplementedError, "#{self.class}#available? must be implemented"
    end

    # Adapter name for logging
    #
    # @return [String] Human-readable adapter name
    def name
      self.class.name.demodulize.sub(/Adapter$/, "")
    end

    protected

    # Validate file exists and is readable
    #
    # @param file_path [String] Path to file
    # @raise [ExtractionError] if file is invalid
    def validate_file!(file_path)
      unless file_path.present? && File.exist?(file_path)
        raise ExtractionError, "File not found: #{file_path}"
      end

      unless File.readable?(file_path)
        raise ExtractionError, "File not readable: #{file_path}"
      end
    end

    # Log extraction attempt
    #
    # @param file_path [String] Path to file being processed
    def log_extraction_start(file_path)
      Rails.logger.info "[#{name}] Starting extraction: #{File.basename(file_path)}"
    end

    # Log extraction success
    #
    # @param items_count [Integer] Number of items extracted
    def log_extraction_success(items_count)
      Rails.logger.info "[#{name}] Extraction successful: #{items_count} items"
    end

    # Log extraction failure
    #
    # @param error [Exception] The error that occurred
    def log_extraction_failure(error)
      Rails.logger.error "[#{name}] Extraction failed: #{error.message}"
      Rails.logger.error error.backtrace&.first(5)&.join("\n") if error.backtrace
    end
  end
end
