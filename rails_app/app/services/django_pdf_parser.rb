require 'net/http'
require 'uri'
require 'json'

class DjangoPdfParser
  class ParseError < StandardError; end

  def initialize
    @django_url = ENV.fetch('DJANGO_API_URL', 'http://localhost:8000')
    @timeout = 120 # 2 minutes
  end

  def parse_pdf(pdf_path, vendor_name: nil)
    # Validate file exists
    unless File.exist?(pdf_path)
      raise ParseError, "PDF file not found: #{pdf_path}"
    end

    # Send PDF to Django API
    uri = URI("#{@django_url}/api/parse/")

    request = Net::HTTP::Post.new(uri)

    # Create multipart form data
    boundary = "----RubyFormBoundary#{SecureRandom.hex(10)}"
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"

    # Build multipart body
    # すべての要素をASCII-8BITエンコーディングに統一してエラーを防ぐ
    body_parts = []

    # Add vendor_name if provided
    if vendor_name
      body_parts << "--#{boundary}\r\n".force_encoding(Encoding::ASCII_8BIT)
      body_parts << "Content-Disposition: form-data; name=\"vendor_name\"\r\n\r\n".force_encoding(Encoding::ASCII_8BIT)
      body_parts << "#{vendor_name}\r\n".force_encoding(Encoding::ASCII_8BIT)
    end

    # Add PDF file
    body_parts << "--#{boundary}\r\n".force_encoding(Encoding::ASCII_8BIT)
    body_parts << "Content-Disposition: form-data; name=\"pdf\"; filename=\"#{File.basename(pdf_path)}\"\r\n".force_encoding(Encoding::ASCII_8BIT)
    body_parts << "Content-Type: application/pdf\r\n\r\n".force_encoding(Encoding::ASCII_8BIT)
    body_parts << File.binread(pdf_path)  # 既にbinary (ASCII-8BIT)
    body_parts << "\r\n--#{boundary}--\r\n".force_encoding(Encoding::ASCII_8BIT)

    request.body = body_parts.join

    # 詳細ログ: リクエスト情報
    Rails.logger.info "=== Django API Request ==="
    Rails.logger.info "URL: #{uri}"
    Rails.logger.info "Method: POST"
    Rails.logger.info "Body size: #{request.body.size} bytes"
    Rails.logger.info "Vendor name: #{vendor_name.inspect}"

    # Send request with timeout
    begin
      response = Net::HTTP.start(uri.hostname, uri.port,
                                  read_timeout: @timeout,
                                  open_timeout: 30) do |http|
        http.request(request)
      end

      # 詳細ログ: レスポンス情報
      Rails.logger.info "=== Django API Response ==="
      Rails.logger.info "Status: #{response.code}"
      Rails.logger.info "Body: #{response.body[0..500]}"
    rescue => e
      Rails.logger.error "=== Django API Connection Error ==="
      Rails.logger.error "Error class: #{e.class}"
      Rails.logger.error "Error message: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace[0..5].join("\n")}"
      raise
    end

    # Handle response
    case response.code.to_i
    when 200
      result = JSON.parse(response.body, symbolize_names: true)

      # Validate response structure
      validate_response!(result)

      result
    when 400..499
      error_data = JSON.parse(response.body) rescue {}
      raise ParseError, "Client error (#{response.code}): #{error_data['error'] || response.body}"
    when 500..599
      error_data = JSON.parse(response.body) rescue {}
      raise ParseError, "Server error (#{response.code}): #{error_data['error'] || 'Django service error'}"
    else
      raise ParseError, "Unexpected response (#{response.code}): #{response.body}"
    end

  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise ParseError, "Timeout connecting to Django service: #{e.message}"
  rescue Errno::ECONNREFUSED => e
    raise ParseError, "Cannot connect to Django service at #{@django_url}: #{e.message}"
  rescue JSON::ParserError => e
    raise ParseError, "Invalid JSON response from Django: #{e.message}"
  end

  def health_check
    uri = URI("#{@django_url}/api/health/")

    response = Net::HTTP.get_response(uri)

    if response.code.to_i == 200
      JSON.parse(response.body, symbolize_names: true)
    else
      { status: 'unhealthy', error: "HTTP #{response.code}" }
    end
  rescue => e
    { status: 'unhealthy', error: e.message }
  end

  private

  def validate_response!(result)
    required_fields = [:vendor_name, :estimate_date, :total_excl_tax, :total_incl_tax, :items]

    required_fields.each do |field|
      unless result.key?(field)
        raise ParseError, "Missing required field in Django response: #{field}"
      end
    end

    # Validate items structure
    unless result[:items].is_a?(Array)
      raise ParseError, "Items must be an array"
    end

    result[:items].each_with_index do |item, idx|
      item_required = [:item_name_raw, :item_name_norm, :cost_type, :amount_excl_tax]
      item_required.each do |field|
        unless item.key?(field)
          raise ParseError, "Item #{idx} missing required field: #{field}"
        end
      end
    end
  end
end
