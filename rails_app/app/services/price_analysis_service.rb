require 'openai'

class PriceAnalysisService
  class AnalysisError < StandardError; end

  def initialize
    @deployment = ENV['AZURE_DEPLOYMENT_NAME'] || 'gpt-4o'
    @api_version = ENV['AZURE_API_VERSION'] || '2024-12-01-preview'

    # エンドポイントの末尾スラッシュ対策とデプロイメントを含む完全なパスの構築
    base_url = ENV['AZURE_OPENAI_ENDPOINT'].to_s.sub(/\/$/, '')
    @uri_base = "#{base_url}/openai/deployments/#{@deployment}"

    # Azure OpenAI用のクライアント設定
    @client = OpenAI::Client.new(
      access_token: ENV['AZURE_OPENAI_API_KEY'],
      uri_base: @uri_base,
      api_type: :azure,
      api_version: @api_version,
      request_timeout: 60
    )
  end

  def analyze_estimate(estimate)
    """
    見積データをAzure OpenAIで分析し、アドバイスを生成

    Args:
      estimate: Estimateモデルのインスタンス

    Returns:
      {
        items_analysis: [
          { item_name: '...', current_price: 100, avg_price: 120, advice: '...' }
        ],
        overall_advice: '全体的な見積評価...'
      }
    """
    items_analysis = []

    estimate.estimate_items.each do |item|
      avg_price = calculate_average_price(item.item_name_norm, item.cost_type)
      advice = get_ai_advice(item, avg_price)

      items_analysis << {
        item_name: item.item_name_raw,
        item_name_norm: item.item_name_norm,
        cost_type: item.cost_type,
        current_price: item.amount_excl_tax,
        avg_price: avg_price,
        quantity: item.quantity || 1,
        advice: advice
      }
    end

    overall_advice = generate_overall_advice(estimate, items_analysis)

    {
      items_analysis: items_analysis,
      overall_advice: overall_advice
    }
  rescue => e
    Rails.logger.error "Price analysis error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      items_analysis: [],
      overall_advice: "分析中にエラーが発生しました。#{e.message}"
    }
  end

  private

  def calculate_average_price(item_name_norm, cost_type)
    """
    過去の見積から平均単価を算出
    """
    avg = EstimateItem
      .where(item_name_norm: item_name_norm, cost_type: cost_type)
      .where.not(amount_excl_tax: nil)
      .average(:amount_excl_tax)

    avg ? avg.to_i : nil
  end

  def get_ai_advice(item, avg_price)
    """
    Azure OpenAI (gpt-4o) を使用して品目ごとのアドバイスを取得
    """
    return "過去データがありません。初回の登録です。" if avg_price.nil?

    prompt = build_item_prompt(item, avg_price)

    begin
      response = @client.chat(
        parameters: {
          model: @deployment,
          messages: [
            { role: "system", content: "あなたは自動車部品の見積価格を分析するエキスパートです。簡潔で具体的なアドバイスを提供してください。" },
            { role: "user", content: prompt }
          ],
          temperature: 0.7,
          max_tokens: 200
        }
      )

      response.dig("choices", 0, "message", "content")&.strip || "分析結果を取得できませんでした。"
    rescue => e
      Rails.logger.error "Azure OpenAI API error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      "AI分析エラー: #{e.message}"
    end
  end

  def build_item_prompt(item, avg_price)
    price_diff = item.amount_excl_tax - avg_price
    price_diff_percent = ((price_diff.to_f / avg_price) * 100).round(1)

    """
商品: #{item.item_name_raw} (#{item.cost_type == 'parts' ? '部品' : '工賃'})
今回の単価: #{item.amount_excl_tax.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}円
過去の平均単価: #{avg_price.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}円
差額: #{price_diff > 0 ? '+' : ''}#{price_diff.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}円 (#{price_diff_percent > 0 ? '+' : ''}#{price_diff_percent}%)

この見積価格は適正でしょうか？
50文字以内で具体的なアドバイスをください。
    """
  end

  def generate_overall_advice(estimate, items_analysis)
    """
    見積全体の総合評価をAIに生成させる
    """
    total_items = items_analysis.size
    higher_than_avg = items_analysis.count { |item| item[:avg_price] && item[:current_price] > item[:avg_price] }
    lower_than_avg = items_analysis.count { |item| item[:avg_price] && item[:current_price] < item[:avg_price] }

    prompt = """
見積業者: #{estimate.vendor_name}
見積日: #{estimate.estimate_date}
合計金額: #{estimate.total_incl_tax.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')}円（税込）

明細数: #{total_items}件
- 平均より高い: #{higher_than_avg}件
- 平均より安い: #{lower_than_avg}件
- データなし: #{total_items - higher_than_avg - lower_than_avg}件

この見積全体について、100文字以内で総合的なアドバイスをください。
    """

    begin
      response = @client.chat(
        parameters: {
          model: @deployment,
          messages: [
            { role: "system", content: "あなたは見積全体を評価する調達担当者です。発注判断に役立つ具体的なアドバイスを提供してください。" },
            { role: "user", content: prompt }
          ],
          temperature: 0.7,
          max_tokens: 300
        }
      )

      response.dig("choices", 0, "message", "content")&.strip || "総合評価を取得できませんでした。"
    rescue => e
      Rails.logger.error "Azure OpenAI API error (overall): #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      "全体的な分析: #{higher_than_avg}件が平均より高く、#{lower_than_avg}件が平均より安い見積です。"
    end
  end
end
