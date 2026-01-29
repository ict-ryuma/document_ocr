# frozen_string_literal: true

# OpenAI Chat Service (Meister Bot)
# Conversational AI chatbot using Azure OpenAI GPT-4o with Function Calling
# Helps users search estimate data through natural language queries
class OpenaiChatService
  class ChatError < StandardError; end

  SYSTEM_PROMPT = <<~PROMPT.freeze
    あなたは「Meister Bot」という名前の、自動車整備工場向けDXコンサルタントAIです。
    見積データベースを活用して、ユーザーの業務を支援するのがあなたの使命です。

    【あなたの役割】
    - ユーザーの曖昧な指示（「東京の工場教えて」「ワイパーの相場は？」など）から、適切な検索や分析を実行する
    - データを見やすく整形して提示する（**必ずMarkdownの表形式を使用**）
    - データに基づいた考察やアドバイスを一言添える
    - 検索結果が0件でも、前向きな提案をする

    【出力形式の厳守】
    1. **検索結果は必ずMarkdown表形式**で出力する
       例：
       | 会社名 | 住所 | 部品名 | 金額 | 日付 |
       |--------|------|--------|------|------|
       | A工場 | 東京都... | ワイパー | 3,500円 | 2025-01-15 |

    2. **表の後に必ず考察を1〜2文**添える
       例：「A社が最安ですが、B社は近場なので配送コストを考えると有力な選択肢です。」

    3. **データがない場合の対応**
       - 「データがありません」で終わらせない
       - 「〇〇というキーワードなら見つかるかもしれません」と代替案を提示

    【回答のトーン】
    - プロフェッショナルだが親しみやすい
    - 簡潔でわかりやすい説明
    - データに基づいた客観的なアドバイス

    【制約】
    - データベースにない情報は推測しない
    - 個人情報や機密情報は扱わない
    - 検索関数は必ず1回の応答で1つだけ実行する
  PROMPT

  FUNCTION_DEFINITIONS = [
    {
      type: "function",
      function: {
        name: "search_estimates",
        description: "見積データベースをキーワードとエリアで検索します。ユーザーが「〇〇の工場を教えて」「東京で△△を扱っているところは？」のような質問をしたら、このfunctionを呼び出してください。リスト形式で複数の結果を返します。",
        parameters: {
          type: "object",
          properties: {
            keyword: {
              type: "string",
              description: "検索キーワード（例：「ワイパー」「ブレーキパッド」「オイル交換」）"
            },
            area: {
              type: "string",
              description: "検索エリア（例：「東京」「大阪」「神奈川」）。ユーザーが指定していない場合は省略可能。"
            },
            limit: {
              type: "integer",
              description: "取得する最大件数（デフォルト: 10件）"
            }
          },
          required: [ "keyword" ]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "find_cheapest_vendor",
        description: "特定のキーワードとエリアで最安値の工場を検索します。ユーザーが「〇〇が一番安い工場は？」のような質問をしたら、このfunctionを呼び出してください。",
        parameters: {
          type: "object",
          properties: {
            keyword: {
              type: "string",
              description: "検索キーワード（例：「ワイパー」「ブレーキパッド」）"
            },
            area: {
              type: "string",
              description: "検索エリア（例：「東京」「大阪」）。省略可能。"
            }
          },
          required: [ "keyword" ]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "analyze_market_price",
        description: "特定の部品やサービスの市場価格を分析します。ユーザーが「〇〇の相場は？」「△△の平均価格を教えて」「傾向を知りたい」のような質問をしたら、このfunctionを呼び出してください。平均価格・最高値・最安値・データ件数を返します。",
        parameters: {
          type: "object",
          properties: {
            keyword: {
              type: "string",
              description: "分析対象のキーワード（例：「ワイパー」「ブレーキパッド」「オイル交換」）"
            },
            area: {
              type: "string",
              description: "分析対象エリア（例：「東京」「大阪」）。省略可能。"
            }
          },
          required: [ "keyword" ]
        }
      }
    }
  ].freeze

  def initialize(chat_thread:)
    @client = setup_openai_client
    @chat_thread = chat_thread
  end

  # Send a message to the chatbot and get a response
  #
  # @param user_message [String] User's message
  # @return [Hash] Response with structure:
  #   {
  #     response: String,              # Bot's response text
  #     function_called: String or nil, # Name of function called (if any)
  #     search_results: Hash or nil     # Search results (if function was called)
  #   }
  def chat(user_message)
    raise ChatError, "User message cannot be blank" if user_message.blank?

    Rails.logger.info "[OpenaiChat] Received message: #{user_message.truncate(100)}"

    # システムプロンプトがなければ追加
    ensure_system_prompt

    # ユーザーメッセージをDBに保存
    user_msg = @chat_thread.chat_messages.create!(
      role: "user",
      content: user_message
    )

    # Call OpenAI API with Function Calling
    response = call_openai_with_functions

    # Handle function calls (if any)
    if response.dig("choices", 0, "finish_reason") == "tool_calls"
      function_result = handle_function_calls(response)

      # Add function result to conversation and get final response
      final_response = call_openai_with_functions

      # アシスタントの最終応答をDBに保存
      assistant_content = final_response.dig("choices", 0, "message", "content")
      @chat_thread.chat_messages.create!(
        role: "assistant",
        content: assistant_content
      )

      {
        response: assistant_content,
        function_called: function_result[:function_name],
        search_results: function_result[:result]
      }
    else
      # No function call, just return the text response
      assistant_content = response.dig("choices", 0, "message", "content")

      # アシスタントの応答をDBに保存
      @chat_thread.chat_messages.create!(
        role: "assistant",
        content: assistant_content
      )

      {
        response: assistant_content,
        function_called: nil,
        search_results: nil
      }
    end
  rescue => e
    Rails.logger.error "[OpenaiChat] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # エラーメッセージもDBに保存
    error_message = "申し訳ない、エラーが発生したよ。もう一度試してくれるかな？"
    @chat_thread.chat_messages.create!(
      role: "assistant",
      content: error_message
    )

    {
      response: error_message,
      function_called: nil,
      search_results: nil,
      error: e.message
    }
  end

  private

  # システムプロンプトが会話履歴になければ追加
  def ensure_system_prompt
    return if @chat_thread.chat_messages.exists?(role: "system")

    @chat_thread.chat_messages.create!(
      role: "system",
      content: SYSTEM_PROMPT
    )
  end

  def setup_openai_client
    # 既存の設定を使用（config/initializers/ocr.rb で定義済み）
    config = Rails.application.config.ocr.azure

    raise ChatError, "Azure OpenAI credentials not configured" unless config[:api_key].present? && config[:endpoint].present? && config[:deployment_name].present?

    # エンドポイントの末尾のスラッシュを除去
    base_url = config[:endpoint].to_s.sub(%r{/$}, "")

    # Azure用パスの構築（デプロイメント名を含む）
    uri_base = "#{base_url}/openai/deployments/#{config[:deployment_name]}"

    OpenAI::Client.new(
      access_token: config[:api_key],
      uri_base: uri_base,
      api_type: :azure,
      api_version: config[:api_version],
      request_timeout: 60
    )
  end

  def call_openai_with_functions
    # DBから最新の会話履歴を取得
    conversation_history = @chat_thread.conversation_history

    Rails.logger.info "[OpenaiChat] Calling OpenAI API (messages: #{conversation_history.size})"

    response = @client.chat(
      parameters: {
        # Azure OpenAI では model パラメータは不要（URIにデプロイメント名が含まれるため）
        messages: conversation_history,
        tools: FUNCTION_DEFINITIONS,
        tool_choice: "auto",
        temperature: 0.7,
        max_tokens: 800
      }
    )

    Rails.logger.info "[OpenaiChat] API response received (finish_reason: #{response.dig('choices', 0, 'finish_reason')})"

    # アシスタントの応答（tool_callsを含む可能性あり）をDBに保存
    assistant_message = response.dig("choices", 0, "message")
    if assistant_message && assistant_message["role"] == "assistant"
      # tool_callsがある場合はJSON文字列として保存
      content = if assistant_message["tool_calls"].present?
        assistant_message["tool_calls"].to_json
      else
        assistant_message["content"]
      end

      @chat_thread.chat_messages.create!(
        role: "assistant",
        content: content || "(no content)"
      )
    end

    response
  end

  def handle_function_calls(response)
    tool_calls = response.dig("choices", 0, "message", "tool_calls")
    return { function_name: nil, result: nil } unless tool_calls

    # Handle first function call (assuming only one at a time)
    tool_call = tool_calls.first
    function_name = tool_call.dig("function", "name")
    arguments = JSON.parse(tool_call.dig("function", "arguments"))

    Rails.logger.info "[OpenaiChat] Function called: #{function_name} with args: #{arguments.inspect}"

    # Execute the function
    result = execute_function(function_name, arguments)

    # Function結果をDBに保存（tool role）
    @chat_thread.chat_messages.create!(
      role: "tool",
      content: result.to_json,
      function_name: tool_call["id"]  # tool_call_id を保存
    )

    { function_name: function_name, result: result }
  end

  def execute_function(function_name, arguments)
    case function_name
    when "search_estimates"
      search_estimates(arguments)
    when "find_cheapest_vendor"
      find_cheapest_vendor(arguments)
    when "analyze_market_price"
      analyze_market_price(arguments)
    else
      Rails.logger.warn "[OpenaiChat] Unknown function: #{function_name}"
      { error: "Unknown function" }
    end
  end

  def search_estimates(args)
    keyword = args["keyword"]
    area = args["area"]
    limit = args["limit"] || 10

    Rails.logger.info "[OpenaiChat] Searching estimates: keyword='#{keyword}', area='#{area}', limit=#{limit}"

    result = EstimateSearchService.search(keyword: keyword, area: area, limit: limit)

    # Format results for GPT
    if result[:results].empty?
      {
        success: false,
        message: "検索結果が見つかりませんでした。",
        keyword: keyword,
        area: area,
        results: []
      }
    else
      {
        success: true,
        message: "#{result[:total_count]}件の結果が見つかりました（上位#{result[:results].size}件を表示）。",
        keyword: keyword,
        area: area,
        total_count: result[:total_count],
        results: result[:results].map do |r|
          {
            vendor_name: r[:vendor_name],
            vendor_address: r[:vendor_address],
            item_name: r[:item_name],
            amount_excl_tax: r[:amount_excl_tax],
            estimate_date: r[:estimate_date]
          }
        end
      }
    end
  end

  def find_cheapest_vendor(args)
    keyword = args["keyword"]
    area = args["area"]

    Rails.logger.info "[OpenaiChat] Finding cheapest vendor: keyword='#{keyword}', area='#{area}'"

    result = EstimateSearchService.find_cheapest(keyword: keyword, area: area)

    if result
      {
        success: true,
        message: "最安値の工場が見つかりました。",
        vendor_name: result[:vendor_name],
        vendor_address: result[:vendor_address],
        item_name: result[:item_name],
        amount_excl_tax: result[:amount_excl_tax],
        quantity: result[:quantity],
        estimate_date: result[:estimate_date]
      }
    else
      {
        success: false,
        message: "該当する工場が見つかりませんでした。",
        keyword: keyword,
        area: area
      }
    end
  end

  def analyze_market_price(args)
    keyword = args["keyword"]
    area = args["area"]

    Rails.logger.info "[OpenaiChat] Analyzing market price: keyword='#{keyword}', area='#{area}'"

    result = EstimateSearchService.analyze_market_price(keyword: keyword, area: area)

    if result[:success]
      {
        success: true,
        message: result[:message],
        keyword: result[:keyword],
        area: result[:area],
        data_count: result[:data_count],
        average_price: result[:average_price],
        min_price: result[:min_price],
        max_price: result[:max_price],
        vendor_count: result[:vendor_count]
      }
    else
      {
        success: false,
        message: result[:message],
        keyword: result[:keyword],
        area: result[:area]
      }
    end
  end
end
