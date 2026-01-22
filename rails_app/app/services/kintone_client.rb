require 'net/http'
require 'json'
require 'uri'

class KintoneClient
  def initialize
    @domain = ENV['KINTONE_DOMAIN']
    @token = ENV['KINTONE_API_TOKEN']
    @app_id = 316
  end

  def push_recommendation(item_name_norm, recommendation_data)
    uri = URI("https://#{@domain}/k/v1/record.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['X-Cybozu-API-Token'] = @token
    request['Content-Type'] = 'application/json'

    record = build_record(item_name_norm, recommendation_data)
    body = {
      app: @app_id,
      record: record
    }

    request.body = body.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    if response.code.to_i >= 200 && response.code.to_i < 300
      { success: true, kintone_record_id: result['id'] }
    else
      { success: false, error: result['message'] || 'Unknown error' }
    end
  rescue => e
    { success: false, error: e.message }
  end

  private

  def build_record(item_name_norm, recommendation_data)
    single = recommendation_data[:single_vendor_best] || {}
    split = recommendation_data[:split_theoretical_best] || {}

    {
      item_name: { value: item_name_norm },
      best_vendor: { value: single[:vendor_name] || '' },
      best_single_total: { value: single[:total] || 0 },
      split_parts_min: { value: split[:parts_min] || 0 },
      split_labor_min: { value: split[:labor_min] || 0 },
      split_total: { value: split[:total] || 0 }
    }
  end
end