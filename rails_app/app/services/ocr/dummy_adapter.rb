# frozen_string_literal: true

module Ocr
  # Development/Test adapter that returns dummy data
  # Always available - used as last resort fallback
  class DummyAdapter < BaseAdapter
    DUMMY_ITEMS = [
      { item_name_raw: "ワイパーブレード", amount_excl_tax: 3800, quantity: 1 },
      { item_name_raw: "ワイパー交換工賃", amount_excl_tax: 2200, quantity: 1 },
      { item_name_raw: "エンジンオイル 5W-30", amount_excl_tax: 4800, quantity: 1 },
      { item_name_raw: "オイル交換工賃", amount_excl_tax: 1500, quantity: 1 },
      { item_name_raw: "エアフィルター", amount_excl_tax: 2800, quantity: 1 }
    ].freeze

    def initialize
      # No configuration needed
    end

    def extract(file_path)
      validate_file!(file_path)
      log_extraction_start(file_path)

      Rails.logger.warn "[#{name}] Using dummy data - no real OCR performed"

      total_excl_tax = DUMMY_ITEMS.sum { |item| item[:amount_excl_tax] }
      total_incl_tax = (total_excl_tax * 1.1).to_i

      result = {
        vendor_address: nil,
        items: DUMMY_ITEMS.dup,
        total_amount_excl_tax: total_excl_tax,
        total_amount_incl_tax: total_incl_tax
      }

      log_extraction_success(result[:items].size)
      result
    end

    def available?
      true
    end
  end
end
