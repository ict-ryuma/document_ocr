class EstimatesController < ApplicationController
  # Skip CSRF verification for API endpoints only
  skip_before_action :verify_authenticity_token, only: [:from_pdf, :from_pdf_upload]

  # Web UI Actions

  def index
    @estimates = Estimate.all.includes(:estimate_items).order(created_at: :desc).limit(50)

    respond_to do |format|
      format.html # Renders app/views/estimates/index.html.erb
      format.json {
        render json: @estimates.map { |e|
          {
            id: e.id,
            vendor_name: e.vendor_name,
            estimate_date: e.estimate_date,
            total_excl_tax: e.total_excl_tax,
            total_incl_tax: e.total_incl_tax,
            items_count: e.estimate_items.count,
            created_at: e.created_at
          }
        }
      }
    end
  end

  def new
    # Web UI upload form
  end

  def create
    # Handle Web UI form submission (multipart file upload)
    # Step 1: Parse PDF and show results for user review (WITHOUT saving to DB)
    uploaded_file = params[:pdf]

    unless uploaded_file
      flash[:error] = 'PDFファイルをアップロードしてください'
      return redirect_to new_estimate_path
    end

    # Save to temporary file
    temp_file = Tempfile.new(['upload', '.pdf'])
    begin
      temp_file.binmode
      temp_file.write(uploaded_file.read)
      temp_file.close

      # Parse using OCR orchestration service (returns draft data, not saved)
      orchestrator = OcrOrchestrationService.new
      @parsed_data = orchestrator.extract(temp_file.path, vendor_name: params[:vendor_name])

      # Store only small metadata in session (not the large parsed data)
      session[:pdf_filename] = uploaded_file.original_filename
      session[:send_to_kintone] = params[:send_to_kintone]

      # Store temp file path for kintone upload later
      session[:temp_pdf_path] = temp_file.path

      # Render review page (edit mode) - DO NOT save to database yet
      # @parsed_data is passed to view via instance variable, not session
      render :review
    rescue OcrOrchestrationService::AllAdaptersFailedError => e
      flash[:error] = "PDF解析エラー: #{e.message}"
      redirect_to new_estimate_path
    rescue => e
      Rails.logger.error "PDF parsing error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      flash[:error] = "エラーが発生しました: #{e.message}"
      redirect_to new_estimate_path
    end
  end

  def preview_file
    # Preview the uploaded PDF/image file
    temp_pdf_path = session[:temp_pdf_path]

    unless temp_pdf_path && File.exist?(temp_pdf_path)
      return render plain: 'File not found', status: :not_found
    end

    # Determine content type based on file extension
    file_ext = File.extname(temp_pdf_path).downcase
    content_type = case file_ext
                   when '.pdf'
                     'application/pdf'
                   when '.jpg', '.jpeg'
                     'image/jpeg'
                   when '.png'
                     'image/png'
                   when '.gif'
                     'image/gif'
                   else
                     'application/octet-stream'
                   end

    # Send file with inline disposition (display in browser)
    send_file temp_pdf_path,
              type: content_type,
              disposition: 'inline',
              filename: session[:pdf_filename] || 'preview'
  end

  def confirm
    # Step 2: Save user-confirmed data to database
    # This action is called after user reviews and edits the parsed data
    # Data comes from form params only (no session parsing needed)
    save_action = params[:save_action]  # "local" or "kintone"
    temp_pdf_path = session[:temp_pdf_path]

    # Create Estimate from user-submitted form data
    @estimate = Estimate.new(
      vendor_name: params[:vendor_name],
      vendor_address: params[:vendor_address],
      estimate_date: params[:estimate_date],
      total_excl_tax: params[:total_excl_tax],
      total_incl_tax: params[:total_incl_tax]
    )

    # Create EstimateItem records from form data
    items = params[:items] || []
    items.each do |item|
      @estimate.estimate_items.build(
        item_name_raw: item[:item_name_raw],
        item_name_norm: item[:item_name_norm],
        cost_type: item[:cost_type],
        amount_excl_tax: item[:amount_excl_tax],
        quantity: item[:quantity] || 1
      )
    end

    if @estimate.save
      # Run AI price analysis
      Rails.logger.info "Running AI price analysis for Estimate #{@estimate.id}"
      analysis_service = PriceAnalysisService.new
      analysis_result = analysis_service.analyze_estimate(@estimate)

      # Store AI analysis in database
      @estimate.update(ai_analysis: analysis_result.to_json)

      # Upload to kintone with file (only if save_action is "kintone")
      if save_action == 'kintone' && temp_pdf_path && File.exist?(temp_pdf_path)
        Rails.logger.info "Uploading to kintone for Estimate #{@estimate.id}"
        kintone_service = KintoneService.new
        kintone_result = kintone_service.push_estimate_with_file(@estimate, temp_pdf_path)

        if kintone_result[:success]
          @estimate.update(kintone_record_id: kintone_result[:kintone_record_id])
          flash[:success] = "見積を保存し、kintoneに送信しました (Record ID: #{kintone_result[:kintone_record_id]})"
        else
          flash[:warning] = "見積は保存されましたが、kintone送信に失敗しました: #{kintone_result[:error]}"
        end
      else
        flash[:success] = '見積を保存しました'
      end

      # Clean up temp file
      if temp_pdf_path && File.exist?(temp_pdf_path)
        File.delete(temp_pdf_path)
      end

      # Clear session data
      session.delete(:pdf_filename)
      session.delete(:send_to_kintone)
      session.delete(:temp_pdf_path)

      redirect_to estimate_path(@estimate)
    else
      flash[:error] = @estimate.errors.full_messages.join(', ')
      redirect_to new_estimate_path
    end
  rescue => e
    Rails.logger.error "Estimate save error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    flash[:error] = "保存エラー: #{e.message}"
    redirect_to new_estimate_path
  end

  def show
    @estimate = Estimate.find(params[:id])

    # Parse AI analysis from JSON
    @ai_analysis = if @estimate.ai_analysis.present?
      JSON.parse(@estimate.ai_analysis, symbolize_names: true)
    else
      nil
    end

    respond_to do |format|
      format.html # Renders app/views/estimates/show.html.erb
      format.json {
        render json: {
          estimate: @estimate.as_json(include: :estimate_items),
          ai_analysis: @ai_analysis
        }
      }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html {
        flash[:error] = '見積が見つかりません'
        redirect_to estimates_path
      }
      format.json {
        render json: { error: 'Estimate not found' }, status: :not_found
      }
    end
  end

  # API Actions (Legacy support)

  def from_pdf
    # Get PDF path from params
    pdf_path = params[:pdf_path]

    unless pdf_path && File.exist?(pdf_path)
      return render json: { error: "PDF file not found: #{pdf_path}" }, status: :bad_request
    end

    # Parse PDF using OCR orchestration service
    begin
      orchestrator = OcrOrchestrationService.new
      parsed_data = orchestrator.extract(pdf_path, vendor_name: params[:vendor_name])
    rescue OcrOrchestrationService::AllAdaptersFailedError => e
      return render json: { error: "PDF parsing failed: #{e.message}" }, status: :internal_server_error
    end

    # Create Estimate record
    estimate = Estimate.new(
      vendor_name: parsed_data[:vendor_name],
      estimate_date: parsed_data[:estimate_date],
      total_excl_tax: parsed_data[:total_excl_tax],
      total_incl_tax: parsed_data[:total_incl_tax]
    )

    # Create EstimateItem records (with quantity from Document AI)
    parsed_data[:items].each do |item|
      estimate.estimate_items.build(
        item_name_raw: item[:item_name_raw],
        item_name_norm: item[:item_name_norm],
        cost_type: item[:cost_type],
        amount_excl_tax: item[:amount_excl_tax],
        quantity: item[:quantity] || 1
      )
    end

    if estimate.save
      render json: {
        estimate_id: estimate.id,
        vendor_name: estimate.vendor_name,
        items_count: estimate.estimate_items.count,
        total_incl_tax: estimate.total_incl_tax
      }, status: :created
    else
      render json: { error: estimate.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def from_pdf_upload
    # Handle multipart file upload (API)
    uploaded_file = params[:pdf]

    unless uploaded_file
      return render json: { error: 'PDF file is required' }, status: :bad_request
    end

    # Save to temporary file
    temp_file = Tempfile.new(['upload', '.pdf'])
    begin
      temp_file.binmode
      temp_file.write(uploaded_file.read)
      temp_file.close

      # Parse using OCR orchestration service
      orchestrator = OcrOrchestrationService.new
      parsed_data = orchestrator.extract(temp_file.path, vendor_name: params[:vendor_name])

      # Create Estimate record
      estimate = Estimate.new(
        vendor_name: parsed_data[:vendor_name],
        estimate_date: parsed_data[:estimate_date],
        total_excl_tax: parsed_data[:total_excl_tax],
        total_incl_tax: parsed_data[:total_incl_tax]
      )

      # Create EstimateItem records (with quantity from Document AI)
      parsed_data[:items].each do |item|
        estimate.estimate_items.build(
          item_name_raw: item[:item_name_raw],
          item_name_norm: item[:item_name_norm],
          cost_type: item[:cost_type],
          amount_excl_tax: item[:amount_excl_tax],
          quantity: item[:quantity] || 1
        )
      end

      if estimate.save
        render json: {
          estimate_id: estimate.id,
          vendor_name: estimate.vendor_name,
          items_count: estimate.estimate_items.count,
          total_incl_tax: estimate.total_incl_tax,
          items: estimate.estimate_items.as_json
        }, status: :created
      else
        render json: { error: estimate.errors.full_messages }, status: :unprocessable_entity
      end
    rescue OcrOrchestrationService::AllAdaptersFailedError => e
      render json: { error: "PDF parsing failed: #{e.message}" }, status: :internal_server_error
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
end
