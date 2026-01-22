# frozen_string_literal: true

# Product name normalization service
# Normalizes raw product names to standard categories and determines cost type
class ProductNormalizerService
  # Normalization rules mapping standard names to keywords
  NORMALIZATION_RULES = {
    "wiper_blade" => %w[
      ワイパー wiper ブレード blade ワイパーブレード
    ],
    "engine_oil" => %w[
      エンジンオイル オイル oil エンジン油
    ],
    "air_filter" => %w[
      エアフィルター エアクリーナー
    ],
    "oil_filter" => %w[
      オイルフィルター オイルエレメント
    ],
    "brake_pad" => %w[
      ブレーキパッド ブレーキ brake
    ],
    "tire" => %w[
      タイヤ tire tyre
    ],
    "battery" => %w[
      バッテリー battery 蓄電池
    ]
  }.freeze

  # Keywords indicating labor/service costs
  LABOR_KEYWORDS = %w[
    工賃 labor labour installation service
    取付 取り付け 交換工賃 作業 手数料 技術料
  ].freeze

  class << self
    # Normalize product name to standard category
    #
    # @param raw_name [String] Raw product name from OCR
    # @return [String] Normalized name (e.g., 'wiper_blade', 'engine_oil')
    def normalize(raw_name)
      return "unknown" if raw_name.blank?

      lower_name = raw_name.downcase.strip

      # Check each normalization rule
      NORMALIZATION_RULES.each do |normalized_name, keywords|
        keywords.each do |keyword|
          return normalized_name if lower_name.include?(keyword.downcase)
        end
      end

      # No match found - create safe normalized name
      safe_name = lower_name.gsub(/[^\w\s]/, "").gsub(/\s+/, "_")
      safe_name.presence || "unknown"
    end

    # Determine if item is parts or labor
    #
    # @param raw_name [String] Raw product name from OCR
    # @return [String] 'labor' or 'parts'
    def determine_cost_type(raw_name)
      return "parts" if raw_name.blank?

      lower_name = raw_name.downcase.strip

      LABOR_KEYWORDS.each do |keyword|
        return "labor" if lower_name.include?(keyword.downcase)
      end

      "parts"
    end

    # Process items array with normalization and cost type determination
    #
    # @param items [Array<Hash>] Raw items from OCR
    # @return [Array<Hash>] Items with item_name_norm and cost_type added
    def process_items(items)
      items.map do |item|
        raw_name = item[:item_name_raw]
        item.merge(
          item_name_norm: normalize(raw_name),
          cost_type: determine_cost_type(raw_name)
        )
      end
    end

    # Extract quantity from text
    #
    # @param text [String] Text potentially containing quantity
    # @return [Integer] Extracted quantity (default 1)
    def extract_quantity(text)
      return 1 if text.blank?

      patterns = [
        /[x×](\d+)/i,         # x2, ×3
        /(\d+)[個本枚台式]/,   # 2個, 3本
        /数量[:\s]*(\d+)/     # 数量:2
      ]

      patterns.each do |pattern|
        match = text.match(pattern)
        return match[1].to_i if match
      end

      1
    end
  end
end
