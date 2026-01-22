require 'net/http'
require 'json'
require 'uri'

class KintoneService
  class KintoneError < StandardError; end

  # kintone App 316 フィールドマッピング (発注書サブテーブル対応)
  FIELD_MAPPING = {
    # メインフィールド
    item_name: 'item_name',
    best_vendor: 'best_vendor',
    best_single_total: 'best_single_total',
    split_parts_min: 'split_parts_min',
    split_labor_min: 'split_labor_min',
    split_total: 'split_total',
    comparison_date: 'comparison_date',
    notes: 'notes',

    # サブテーブル「発注書」
    subtable_order: '発注書',

    # サブテーブル内フィールド (Document AI対応)
    item_name_field: '品名・加工方法',       # Document AIで解析した品名
    quantity_field: '数量',                  # Document AIで解析した数量
    unit_price_field: '単価',                # Document AIで解析した単価
    tax_category_field: '課税区分',          # 課税区分（固定: 課税）
    normalized_name_field: '正規化品名',     # システムで正規化した品名
    cost_type_field: '費目'                  # 部品/工賃の区分
  }.freeze

  def initialize
    @domain = ENV['KINTONE_DOMAIN']
    @token = ENV['KINTONE_API_TOKEN']
    @app_id = 316

    validate_credentials!
  end

  def push_recommendation(item_name_norm, recommendation_data, estimate_items: [])
    """
    最安比較結果をkintoneにプッシュ（サブテーブル「発注書」対応）

    Args:
      item_name_norm: 正規化品名 (例: wiper_blade)
      recommendation_data: 最安比較結果 { single_vendor_best: {...}, split_theoretical_best: {...} }
      estimate_items: EstimateItemの配列 (Document AI解析データ)

    Returns:
      { success: true/false, kintone_record_id: "...", ... }
    """

    # メインフィールドを構築
    record = build_main_fields(item_name_norm, recommendation_data)

    # サブテーブル「発注書」にDocument AI解析データをマッピング
    if estimate_items.any?
      record[FIELD_MAPPING[:subtable_order]] = {
        value: build_subtable_rows(estimate_items)
      }
    end

    # kintoneにレコード作成
    result = create_record(record)

    if result[:success]
      {
        success: true,
        kintone_record_id: result[:record_id],
        item_name: item_name_norm,
        details_count: estimate_items.size,
        subtable_name: '発注書'
      }
    else
      {
        success: false,
        error: result[:error]
      }
    end
  rescue => e
    Rails.logger.error "KintoneService error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: "KintoneService error: #{e.message}"
    }
  end

  def push_estimate_with_file(estimate, pdf_file_path)
    """
    見積データとPDFファイルをkintoneにアップロード（Web UI用）

    Args:
      estimate: Estimateモデルのインスタンス
      pdf_file_path: PDFファイルのパス

    Returns:
      { success: true/false, kintone_record_id: "...", file_key: "..." }
    """

    # Step 1: Upload PDF file to kintone
    file_upload_result = upload_file(pdf_file_path)

    unless file_upload_result[:success]
      return {
        success: false,
        error: "File upload failed: #{file_upload_result[:error]}"
      }
    end

    file_key = file_upload_result[:file_key]

    # Step 2: Create record with file attachment
    record = {
      # File attachment field (仮にフィールドコードを 'pdf_file' と想定)
      'pdf_file' => {
        value: [{ fileKey: file_key }]
      }
    }

    # Step 3: Add subtable data
    if estimate.estimate_items.any?
      record[FIELD_MAPPING[:subtable_order]] = {
        value: build_subtable_rows(estimate.estimate_items)
      }
    end

    # Step 4: Create kintone record
    result = create_record(record)

    if result[:success]
      {
        success: true,
        kintone_record_id: result[:record_id],
        file_key: file_key,
        items_count: estimate.estimate_items.size
      }
    else
      {
        success: false,
        error: result[:error]
      }
    end
  rescue => e
    Rails.logger.error "push_estimate_with_file error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: "push_estimate_with_file error: #{e.message}"
    }
  end

  def upload_file(file_path)
    """
    kintone File APIにファイルをアップロード

    Args:
      file_path: アップロードするファイルのパス

    Returns:
      { success: true/false, file_key: "..." }
    """
    unless File.exist?(file_path)
      return { success: false, error: "File not found: #{file_path}" }
    end

    uri = URI("https://#{@domain}/k/v1/file.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request['X-Cybozu-API-Token'] = @token

    # Create multipart form data
    boundary = "----RubyFormBoundary#{SecureRandom.hex(16)}"
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"

    file_content = File.binread(file_path)
    file_name = File.basename(file_path)

    # すべての要素をASCII-8BITエンコーディングに統一してエラーを防ぐ
    body = []
    body << "--#{boundary}\r\n".force_encoding(Encoding::ASCII_8BIT)
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{file_name}\"\r\n".force_encoding(Encoding::ASCII_8BIT)
    body << "Content-Type: application/pdf\r\n\r\n".force_encoding(Encoding::ASCII_8BIT)
    body << file_content  # 既にbinary (ASCII-8BIT)
    body << "\r\n--#{boundary}--\r\n".force_encoding(Encoding::ASCII_8BIT)

    request.body = body.join

    Rails.logger.info "Uploading file to kintone: #{file_name} (#{file_content.size} bytes)"

    response = http.request(request)
    result = JSON.parse(response.body)

    if response.code.to_i >= 200 && response.code.to_i < 300
      file_key = result['fileKey']
      Rails.logger.info "File uploaded successfully: fileKey=#{file_key}"
      { success: true, file_key: file_key }
    else
      error_msg = result['message'] || result['error'] || 'Unknown error'
      Rails.logger.error "kintone file upload error: #{error_msg} (#{response.code})"
      { success: false, error: error_msg }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "kintone file upload timeout: #{e.message}"
    { success: false, error: "Timeout: #{e.message}" }
  rescue JSON::ParserError => e
    Rails.logger.error "kintone file upload JSON parse error: #{e.message}"
    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue => e
    Rails.logger.error "kintone file upload error: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  def health_check
    """kintone接続確認"""
    uri = URI("https://#{@domain}/k/v1/app.json?id=#{@app_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri.path + '?' + uri.query)
    request['X-Cybozu-API-Token'] = @token

    response = http.request(request)

    if response.code.to_i == 200
      { status: 'healthy', app_id: @app_id, app_name: '発注管理' }
    else
      { status: 'unhealthy', error: "HTTP #{response.code}" }
    end
  rescue => e
    { status: 'unhealthy', error: e.message }
  end

  private

  def validate_credentials!
    if @domain.nil? || @domain.empty?
      raise KintoneError, "KINTONE_DOMAIN environment variable not set"
    end

    if @token.nil? || @token.empty?
      raise KintoneError, "KINTONE_API_TOKEN environment variable not set"
    end
  end

  def build_main_fields(item_name_norm, recommendation_data)
    """
    メインフィールドを構築

    最安比較結果をkintoneメインフィールドにマッピング
    """
    single = recommendation_data[:single_vendor_best] || {}
    split = recommendation_data[:split_theoretical_best] || {}

    {
      FIELD_MAPPING[:item_name] => { value: item_name_norm },
      FIELD_MAPPING[:best_vendor] => { value: single[:vendor_name] || '' },
      FIELD_MAPPING[:best_single_total] => { value: single[:total] || 0 },
      FIELD_MAPPING[:split_parts_min] => { value: split[:parts_min] || 0 },
      FIELD_MAPPING[:split_labor_min] => { value: split[:labor_min] || 0 },
      FIELD_MAPPING[:split_total] => { value: split[:total] || 0 },
      FIELD_MAPPING[:comparison_date] => { value: Date.today.strftime('%Y-%m-%d') },
      FIELD_MAPPING[:notes] => {
        value: generate_notes(item_name_norm, single, split)
      }
    }
  end

  def build_subtable_rows(estimate_items)
    """
    サブテーブル「発注書」の行を構築

    Document AI解析データをkintoneサブテーブルにマッピング:
    - 品名・加工方法 <- item_name_raw
    - 数量 <- quantity (Document AI解析)
    - 単価 <- amount_excl_tax
    - 課税区分 <- 固定で「課税」
    - 正規化品名 <- item_name_norm
    - 費目 <- cost_type (parts/labor)
    """
    estimate_items.map do |item|
      # EstimateItemオブジェクトまたはハッシュに対応
      vendor_name = item.try(:estimate)&.vendor_name || item[:vendor_name] || ''
      item_name_raw = item.try(:item_name_raw) || item[:item_name_raw] || ''
      item_name_norm = item.try(:item_name_norm) || item[:item_name_norm] || ''
      cost_type = item.try(:cost_type) || item[:cost_type] || 'parts'
      amount = item.try(:amount_excl_tax) || item[:amount_excl_tax] || 0
      quantity = item.try(:quantity) || item[:quantity] || 1

      {
        value: {
          # Document AI解析結果を「発注書」サブテーブルにマッピング
          FIELD_MAPPING[:item_name_field] => {
            value: item_name_raw  # 品名・加工方法
          },
          FIELD_MAPPING[:quantity_field] => {
            value: quantity  # 数量
          },
          FIELD_MAPPING[:unit_price_field] => {
            value: amount  # 単価（税抜）
          },
          FIELD_MAPPING[:tax_category_field] => {
            value: '課税'  # 課税区分（固定）
          },
          FIELD_MAPPING[:normalized_name_field] => {
            value: item_name_norm  # 正規化品名 (wiper_blade等)
          },
          FIELD_MAPPING[:cost_type_field] => {
            value: cost_type  # 費目 (parts/labor)
          }
        }
      }
    end
  end

  def generate_notes(item_name, single, split)
    """備考欄の自動生成"""
    notes = []
    notes << "【自動生成】Document AI解析結果"
    notes << "品名: #{item_name}"
    notes << "生成日時: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    notes << ""
    notes << "■ 単一業者最安"
    notes << "  業者名: #{single[:vendor_name]}"
    notes << "  合計: ¥#{single[:total]&.to_s&.reverse&.gsub(/(\d{3})(?=\d)/, '\1,')&.reverse || '0'}"
    notes << ""
    notes << "■ 分割最安（理論値）"
    notes << "  部品代: ¥#{split[:parts_min]&.to_s&.reverse&.gsub(/(\d{3})(?=\d)/, '\1,')&.reverse || '0'}"
    notes << "  工賃: ¥#{split[:labor_min]&.to_s&.reverse&.gsub(/(\d{3})(?=\d)/, '\1,')&.reverse || '0'}"
    notes << "  合計: ¥#{split[:total]&.to_s&.reverse&.gsub(/(\d{3})(?=\d)/, '\1,')&.reverse || '0'}"
    notes << ""
    notes << "※ サブテーブル「発注書」に解析明細を格納"

    notes.join("\n")
  end

  def create_record(record_data)
    """kintoneにレコードを作成"""
    uri = URI("https://#{@domain}/k/v1/record.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri.path)
    request['X-Cybozu-API-Token'] = @token
    request['Content-Type'] = 'application/json'

    body = {
      app: @app_id,
      record: record_data
    }

    Rails.logger.info "Kintone API Request: #{body.to_json[0..500]}..."
    request.body = body.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    if response.code.to_i >= 200 && response.code.to_i < 300
      Rails.logger.info "Kintone record created: #{result['id']}"
      { success: true, record_id: result['id'] }
    else
      error_msg = result['message'] || result['error'] || 'Unknown error'
      Rails.logger.error "Kintone API error: #{error_msg} (#{response.code})"
      Rails.logger.error "Response body: #{response.body}"
      { success: false, error: error_msg }
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "Kintone timeout: #{e.message}"
    { success: false, error: "Timeout: #{e.message}" }
  rescue JSON::ParserError => e
    Rails.logger.error "Kintone JSON parse error: #{e.message}"
    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue => e
    Rails.logger.error "Kintone error: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end
end
