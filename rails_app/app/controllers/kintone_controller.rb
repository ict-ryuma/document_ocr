class KintoneController < ApplicationController
  # POST /kintone/push?item=wiper_blade
  def push
    item_name = params[:item]

    if item_name.blank?
      return render json: { error: "item parameter is required" }, status: :bad_request
    end

    # Compute recommendations
    query_service = EstimatePriceQuery.new(item_name)
    recommendations = query_service.execute

    if recommendations[:error]
      return render json: { error: recommendations[:error] }, status: :not_found
    end

    # Get all items for this normalized name for subtable
    estimate_items = EstimateItem.includes(:estimate)
                                  .where(item_name_norm: item_name)
                                  .order("estimates.estimate_date DESC")

    # Push to kintone with subtable
    kintone_service = KintoneService.new
    result = kintone_service.push_recommendation(
      item_name,
      recommendations,
      estimate_items: estimate_items
    )

    if result[:success]
      render json: {
        success: true,
        kintone_record_id: result[:kintone_record_id],
        item_name: result[:item_name],
        details_count: result[:details_count]
      }, status: :created
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: "Kintone push failed: #{e.message}" }, status: :internal_server_error
  end

  # GET /kintone/health
  def health
    kintone_service = KintoneService.new
    result = kintone_service.health_check

    render json: result
  rescue => e
    render json: { status: "unhealthy", error: e.message }
  end
end
