class NlController < ApplicationController
  # GET /nl/query?q=一番安いワイパーブレード
  def query
    query_text = params[:q]

    if query_text.blank?
      return render json: { error: 'q parameter is required' }, status: :bad_request
    end

    # Simple rule-based mapping (no LLM for MVP)
    item_name = extract_item_name(query_text)

    if item_name.nil? || !query_text.include?('一番安い')
      return render json: { error: 'unsupported query' }, status: :bad_request
    end

    # Delegate to recommendations logic
    query_service = EstimatePriceQuery.new(item_name)
    result = query_service.execute

    if result[:error]
      render json: { error: result[:error] }, status: :not_found
    else
      render json: result
    end
  rescue => e
    render json: { error: "NL query failed: #{e.message}" }, status: :internal_server_error
  end

  private

  def extract_item_name(text)
    # Simple keyword matching for MVP
    if text =~ /(ワイパー|wiper|ブレード|blade)/i
      return 'wiper_blade'
    end

    nil
  end
end
