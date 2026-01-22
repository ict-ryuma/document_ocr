class KintoneController < ApplicationController
  # POST /kintone/push?item=wiper_blade
  def push
    item_name = params[:item]

    if item_name.blank?
      return render json: { error: 'item parameter is required' }, status: :bad_request
    end

    # Compute recommendations
    query_service = EstimatePriceQuery.new(item_name)
    recommendations = query_service.execute

    if recommendations[:error]
      return render json: { error: recommendations[:error] }, status: :not_found
    end

    # Push to kintone
    kintone_client = KintoneClient.new
    result = kintone_client.push_recommendation(item_name, recommendations)

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: { kintone_record_id: result[:record_id] }, status: :created
    end
  rescue => e
    render json: { error: "Kintone push failed: #{e.message}" }, status: :internal_server_error
  end
end
