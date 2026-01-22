require 'json'
require 'open3'

class EstimateImporter
  def initialize(pdf_path)
    @pdf_path = pdf_path
  end

  def import
    # Call Python engine
    python_result = call_python_engine

    if python_result[:error]
      return { error: python_result[:error] }
    end

    parsed_data = python_result[:data]

    # Persist to database
    estimate = nil
    ActiveRecord::Base.transaction do
      estimate = Estimate.create!(
        vendor_name: parsed_data['vendor_name'],
        estimate_date: Date.parse(parsed_data['estimate_date']),
        total_excl_tax: parsed_data['total_excl_tax'],
        total_incl_tax: parsed_data['total_incl_tax']
      )

      parsed_data['items'].each do |item|
        estimate.estimate_items.create!(
          item_name_raw: item['item_name_raw'],
          item_name_norm: item['item_name_norm'],
          cost_type: item['cost_type'],
          amount_excl_tax: item['amount_excl_tax']
        )
      end
    end

    { estimate: estimate }
  rescue => e
    { error: "Database error: #{e.message}" }
  end

  private

  def call_python_engine
    python_script = Rails.root.join('..', 'python_engine', 'main.py').to_s
    cmd = "python3 #{python_script} --pdf #{@pdf_path}"

    stdout, stderr, status = Open3.capture3(cmd)

    unless status.success?
      return { error: "Python engine failed: #{stderr}" }
    end

    begin
      data = JSON.parse(stdout)
      if data['error']
        return { error: data['error'] }
      end
      { data: data }
    rescue JSON::ParserError => e
      { error: "Invalid JSON from Python engine: #{e.message}" }
    end
  end
end
