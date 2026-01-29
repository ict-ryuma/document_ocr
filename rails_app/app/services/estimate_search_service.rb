# frozen_string_literal: true

# Estimate Search Service
# Search estimates by keyword (item name) and area (vendor address)
# Used by Meister Bot chatbot to answer user questions
class EstimateSearchService
  # Search estimates by keyword and/or area
  #
  # @param keyword [String, nil] Search keyword for item names, vendor names, or addresses
  #                              (e.g., "ワイパー", "ブレーキ", "東武スズキ", "埼玉県")
  # @param area [String, nil] Search area for vendor address (e.g., "東京", "大阪")
  #                           If keyword already contains location info, area can be nil
  # @param limit [Integer] Maximum number of results to return (default: 10)
  # @return [Hash] Search results with structure:
  #   {
  #     results: [{ vendor_name:, vendor_address:, estimate_date:, item_name:, amount_excl_tax:, estimate_id: }],
  #     total_count: Integer,
  #     search_params: { keyword:, area: }
  #   }
  def self.search(keyword: nil, area: nil, limit: 10)
    Rails.logger.info "[EstimateSearch] Starting search with keyword='#{keyword}', area='#{area}', limit=#{limit}"

    # Start with all estimates and their items
    # Use left_outer_joins to include estimates even if they have no items
    query = Estimate.left_outer_joins(:estimate_items)

    # Filter by keyword if provided
    # Search across: item names, vendor names, AND vendor addresses
    if keyword.present?
      normalized_keyword = normalize_keyword(keyword)
      query = query.where(
        "estimate_items.item_name_raw LIKE ? OR estimate_items.item_name_norm LIKE ? OR estimates.vendor_name LIKE ? OR estimates.vendor_address LIKE ?",
        "%#{normalized_keyword}%",
        "%#{normalized_keyword}%",
        "%#{normalized_keyword}%",
        "%#{normalized_keyword}%"
      )
      Rails.logger.info "[EstimateSearch] Applied keyword filter (items + vendor + address): #{normalized_keyword}"
    end

    # Filter by area if provided
    if area.present?
      normalized_area = normalize_area(area)
      query = query.where("estimates.vendor_address LIKE ?", "%#{normalized_area}%")
      Rails.logger.info "[EstimateSearch] Applied area filter: #{normalized_area}"
    end

    # Get total count before limit (count distinct estimates)
    total_count = query.select("estimates.id").distinct.count

    # Order by estimate date (newest first) and limit results
    # Select both estimate and item columns (include created_at for ORDER BY compatibility)
    records = query.order("estimates.estimate_date DESC, estimates.created_at DESC")
                   .limit(limit)
                   .select("estimates.id as estimate_id,
                            estimates.vendor_name,
                            estimates.vendor_address,
                            estimates.estimate_date,
                            estimates.created_at,
                            estimate_items.id as item_id,
                            estimate_items.item_name_raw,
                            estimate_items.item_name_norm,
                            estimate_items.cost_type,
                            estimate_items.amount_excl_tax,
                            estimate_items.quantity")
                   .distinct

    # Format results
    results = records.map do |record|
      {
        vendor_name: record.vendor_name,
        vendor_address: record.vendor_address,
        estimate_date: record.estimate_date,
        item_name: record.item_name_raw,
        item_name_norm: record.item_name_norm,
        cost_type: record.cost_type,
        amount_excl_tax: record.amount_excl_tax,
        quantity: record.quantity,
        estimate_id: record.estimate_id
      }
    end

    Rails.logger.info "[EstimateSearch] Found #{total_count} results (showing #{results.size})"

    {
      results: results,
      total_count: total_count,
      search_params: {
        keyword: keyword,
        area: area,
        limit: limit
      }
    }
  end

  # Find cheapest vendor for a specific item in a specific area
  #
  # @param keyword [String] Item name keyword (e.g., "ワイパー")
  # @param area [String, nil] Area filter (e.g., "東京")
  # @return [Hash, nil] Cheapest vendor info or nil if not found
  def self.find_cheapest(keyword:, area: nil)
    Rails.logger.info "[EstimateSearch] Finding cheapest vendor for keyword='#{keyword}', area='#{area}'"

    query = EstimateItem.joins(:estimate)

    # Filter by keyword
    normalized_keyword = normalize_keyword(keyword)
    query = query.where("estimate_items.item_name_raw LIKE ? OR estimate_items.item_name_norm LIKE ?",
                        "%#{normalized_keyword}%", "%#{normalized_keyword}%")

    # Filter by area if provided
    if area.present?
      normalized_area = normalize_area(area)
      query = query.where("estimates.vendor_address LIKE ?", "%#{normalized_area}%")
    end

    # Find cheapest (minimum amount_excl_tax)
    cheapest = query.order("estimate_items.amount_excl_tax ASC")
                    .select("estimate_items.*, estimates.vendor_name, estimates.vendor_address, estimates.estimate_date, estimates.id as estimate_id")
                    .first

    return nil unless cheapest

    result = {
      vendor_name: cheapest.vendor_name,
      vendor_address: cheapest.vendor_address,
      estimate_date: cheapest.estimate_date,
      item_name: cheapest.item_name_raw,
      amount_excl_tax: cheapest.amount_excl_tax,
      quantity: cheapest.quantity,
      estimate_id: cheapest.estimate_id
    }

    Rails.logger.info "[EstimateSearch] Found cheapest: #{result[:vendor_name]} @ ¥#{result[:amount_excl_tax]}"
    result
  end

  # Get summary statistics by vendor and area
  #
  # @param keyword [String] Item name keyword
  # @param area [String, nil] Area filter
  # @return [Hash] Statistics with structure:
  #   {
  #     average_price: Float,
  #     min_price: Integer,
  #     max_price: Integer,
  #     vendor_count: Integer,
  #     total_items: Integer
  #   }
  def self.statistics(keyword:, area: nil)
    Rails.logger.info "[EstimateSearch] Calculating statistics for keyword='#{keyword}', area='#{area}'"

    query = EstimateItem.joins(:estimate)

    # Filter by keyword
    normalized_keyword = normalize_keyword(keyword)
    query = query.where("estimate_items.item_name_raw LIKE ? OR estimate_items.item_name_norm LIKE ?",
                        "%#{normalized_keyword}%", "%#{normalized_keyword}%")

    # Filter by area if provided
    if area.present?
      normalized_area = normalize_area(area)
      query = query.where("estimates.vendor_address LIKE ?", "%#{normalized_area}%")
    end

    # Calculate statistics
    stats = query.select("AVG(estimate_items.amount_excl_tax) as avg_price,
                          MIN(estimate_items.amount_excl_tax) as min_price,
                          MAX(estimate_items.amount_excl_tax) as max_price,
                          COUNT(DISTINCT estimates.id) as vendor_count,
                          COUNT(estimate_items.id) as total_items")
                 .first

    return nil unless stats

    {
      average_price: stats.avg_price&.to_f || 0,
      min_price: stats.min_price || 0,
      max_price: stats.max_price || 0,
      vendor_count: stats.vendor_count || 0,
      total_items: stats.total_items || 0
    }
  end

  # Analyze market price for a specific keyword and area
  # This is a wrapper around statistics() with more detailed result formatting
  #
  # @param keyword [String] Item name keyword (e.g., "ワイパー", "ブレーキパッド")
  # @param area [String, nil] Area filter (e.g., "東京", "大阪")
  # @return [Hash] Market analysis with structure:
  #   {
  #     success: Boolean,
  #     keyword: String,
  #     area: String or nil,
  #     data_count: Integer,
  #     average_price: Integer,
  #     min_price: Integer,
  #     max_price: Integer,
  #     vendor_count: Integer,
  #     message: String
  #   }
  def self.analyze_market_price(keyword:, area: nil)
    Rails.logger.info "[EstimateSearch] Analyzing market price for keyword='#{keyword}', area='#{area}'"

    stats = statistics(keyword: keyword, area: area)

    if stats.nil? || stats[:total_items] == 0
      return {
        success: false,
        keyword: keyword,
        area: area,
        data_count: 0,
        average_price: 0,
        min_price: 0,
        max_price: 0,
        vendor_count: 0,
        message: "該当するデータが見つかりませんでした。"
      }
    end

    {
      success: true,
      keyword: keyword,
      area: area,
      data_count: stats[:total_items],
      average_price: stats[:average_price].round,
      min_price: stats[:min_price],
      max_price: stats[:max_price],
      vendor_count: stats[:vendor_count],
      message: "#{stats[:total_items]}件のデータから相場を分析しました。"
    }
  end

  private

  # Normalize keyword for search (remove spaces, convert katakana variations)
  def self.normalize_keyword(keyword)
    return "" unless keyword.present?

    # Remove spaces
    normalized = keyword.gsub(/\s+/, "")

    # Convert half-width katakana to full-width (if needed)
    # For now, just return as-is since item_name_norm already handles this

    normalized
  end

  # Normalize area for search (handle common abbreviations and variations)
  def self.normalize_area(area)
    return "" unless area.present?

    # Remove spaces
    normalized = area.gsub(/\s+/, "")

    # Handle common abbreviations (expand for more flexibility)
    area_mappings = {
      "東京" => "東京",
      "大阪" => "大阪",
      "神奈川" => "神奈川",
      "埼玉" => "埼玉",
      "千葉" => "千葉"
    }

    # Return mapped value or original
    area_mappings[normalized] || normalized
  end
end
