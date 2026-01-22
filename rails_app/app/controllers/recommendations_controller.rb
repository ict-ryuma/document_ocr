class RecommendationsController < ApplicationController
  # GET /recommendations/by_item?item=wiper_blade
  def by_item
    item_name = params[:item]

    if item_name.blank?
      return render json: { error: 'item parameter is required' }, status: :bad_request
    end

    query_service = EstimatePriceQuery.new(item_name)
    result = query_service.execute

    if result[:error]
      render json: { error: result[:error] }, status: :not_found
    else
      render json: result
    end
  rescue => e
    render json: { error: "Query failed: #{e.message}" }, status: :internal_server_error
  end
end
