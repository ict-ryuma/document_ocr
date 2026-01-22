class EstimatesController < ApplicationController
  # POST /estimates/from_pdf
  # Body: {"pdf_path": "../dummy.pdf"}
  def from_pdf
    pdf_path = params[:pdf_path]

    if pdf_path.blank?
      return render json: { error: 'pdf_path is required' }, status: :bad_request
    end

    importer = EstimateImporter.new(pdf_path)
    result = importer.import

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: { estimate_id: result[:estimate].id }, status: :created
    end
  rescue => e
    render json: { error: "Import failed: #{e.message}" }, status: :internal_server_error
  end

  # GET /estimates
  def index
    estimates = Estimate.includes(:estimate_items).order(estimate_date: :desc)

    render json: estimates.map { |est|
      {
        id: est.id,
        vendor_name: est.vendor_name,
        estimate_date: est.estimate_date,
        total_excl_tax: est.total_excl_tax,
        total_incl_tax: est.total_incl_tax,
        items_count: est.estimate_items.count,
        created_at: est.created_at
      }
    }
  end
end
