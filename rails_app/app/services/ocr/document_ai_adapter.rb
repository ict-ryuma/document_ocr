# frozen_string_literal: true

require "google/cloud/document_ai"

module Ocr
  # Fallback OCR adapter using Google Cloud Document AI
  # Provides table extraction and form field parsing
  class DocumentAiAdapter < BaseAdapter
    def initialize
      @config = Rails.application.config.ocr.document_ai
      @timeout = Rails.application.config.ocr.timeouts[:document_ai]
      @client = build_client if available?
    end

    def extract(file_path)
      validate_file!(file_path)
      log_extraction_start(file_path)

      unless @client
        raise ConfigurationError, "Document AI client not configured"
      end

      # Process document
      document = process_document(file_path)

      # Extract data from document
      result = extract_from_document(document)

      log_extraction_success(result[:items]&.size || 0)
      result
    rescue Google::Cloud::Error => e
      log_extraction_failure(e)
      raise ExtractionError, "Document AI error: #{e.message}"
    rescue StandardError => e
      log_extraction_failure(e)
      raise ExtractionError, "Document AI extraction failed: #{e.message}"
    end

    def available?
      @config[:project_id].present? &&
        @config[:processor_id].present? &&
        @config[:credentials_path].present? &&
        File.exist?(@config[:credentials_path].to_s)
    end

    private

    def build_client
      Google::Cloud::DocumentAI.document_processor_service do |config|
        config.endpoint = "#{@config[:location]}-documentai.googleapis.com"
        config.timeout = @timeout
      end
    end

    def processor_name
      @client.processor_path(
        project: @config[:project_id],
        location: @config[:location],
        processor: @config[:processor_id]
      )
    end

    def process_document(file_path)
      content = File.binread(file_path)
      mime_type = detect_mime_type(file_path)

      request = {
        name: processor_name,
        raw_document: {
          content: content,
          mime_type: mime_type
        }
      }

      response = @client.process_document(request)
      response.document
    end

    def detect_mime_type(file_path)
      ext = File.extname(file_path).downcase
      case ext
      when ".pdf" then "application/pdf"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".png" then "image/png"
      when ".gif" then "image/gif"
      else "application/pdf"
      end
    end

    def extract_from_document(document)
      full_text = document.text
      tables = extract_tables(document)
      form_fields = extract_form_fields(document)

      # Extract line items from tables
      items = extract_line_items(tables, full_text)

      # Calculate totals from items
      total_excl_tax = items.sum { |item| item[:amount_excl_tax] }
      total_incl_tax = (total_excl_tax * 1.1).to_i

      {
        vendor_address: nil,
        items: items,
        total_amount_excl_tax: total_excl_tax,
        total_amount_incl_tax: total_incl_tax
      }
    end

    def extract_tables(document)
      tables = []

      document.pages.each do |page|
        next unless page.tables.any?

        page.tables.each do |table|
          table_data = []

          table.body_rows.each do |row|
            row_data = row.cells.map do |cell|
              get_text(cell.layout, document.text).strip
            end
            table_data << row_data
          end

          tables << table_data
        end
      end

      tables
    end

    def extract_form_fields(document)
      fields = {}

      document.pages.each do |page|
        next unless page.form_fields.any?

        page.form_fields.each do |field|
          name = get_text(field.field_name, document.text).strip
          value = get_text(field.field_value, document.text).strip

          fields[name] = value if name.present? && value.present?
        end
      end

      fields
    end

    def get_text(layout, full_text)
      return "" unless layout&.text_anchor&.text_segments&.any?

      layout.text_anchor.text_segments.map do |segment|
        start_idx = segment.start_index.to_i
        end_idx = segment.end_index.to_i
        full_text[start_idx...end_idx]
      end.join
    end

    def extract_line_items(tables, full_text)
      items = []

      # Try table extraction first
      tables.each do |table|
        table.each do |row|
          item = parse_table_row(row)
          items << item if item
        end
      end

      # If no items from tables, try text parsing
      items = parse_text_items(full_text) if items.empty?

      items
    end

    def parse_table_row(row)
      return nil if row.size < 2

      item_name = nil
      amount = nil
      quantity = 1

      row.each do |cell|
        # Try to extract price
        if (price_match = cell.match(/[¥￥]?\s*([0-9,]+)/))
          amount ||= price_match[1].delete(",").to_i
        # Try to extract item name (non-numeric text)
        elsif cell.length > 2 && !cell.match?(/^[\d,¥￥\s]+$/)
          item_name ||= cell
        end

        # Try to extract quantity
        if (qty_match = cell.match(/[x×]?\s*(\d+)\s*[個本枚]?/))
          quantity = qty_match[1].to_i
        end
      end

      return nil unless item_name && amount && amount < 1_000_000

      {
        item_name_raw: item_name.strip,
        amount_excl_tax: amount,
        quantity: quantity
      }
    end

    def parse_text_items(full_text)
      items = []
      skip_keywords = %w[合計 小計 Total Subtotal 消費税 Tax TEL FAX]

      full_text.each_line do |line|
        cleaned = line.gsub(/(\d),\s+(\d)/, '\1,\2').strip
        next if cleaned.length < 3
        next if skip_keywords.any? { |kw| cleaned.include?(kw) }

        # Extract price
        price_match = cleaned.match(/[¥￥]?\s*([0-9,]+)/)
        next unless price_match

        amount = price_match[1].delete(",").to_i
        next if amount > 1_000_000 || amount < 100

        # Extract item name (text before price)
        item_name = cleaned[0...price_match.begin(0)].strip
        item_name = item_name.sub(/[+\-\s]+$/, "").strip
        next if item_name.length < 2

        items << {
          item_name_raw: item_name,
          amount_excl_tax: amount,
          quantity: 1
        }
      end

      items
    end
  end
end
