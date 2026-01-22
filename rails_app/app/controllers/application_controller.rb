class ApplicationController < ActionController::Base
  def health
    # Check database connection by executing a simple query
    db_healthy = begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      true
    rescue StandardError
      false
    end

    # Check OCR adapters availability
    ocr_available = begin
      OcrOrchestrationService.new.available_adapters.any?
    rescue StandardError
      false
    end

    healthy = db_healthy

    # In production, only return minimal status to avoid information leakage
    if Rails.env.production?
      status_code = healthy ? :ok : :service_unavailable
      render json: { status: healthy ? "ok" : "error" }, status: status_code
    else
      render json: {
        status: healthy ? "healthy" : "degraded",
        services: {
          database: db_healthy ? "connected" : "disconnected",
          ocr_adapters: ocr_available ? "available" : "unavailable"
        },
        timestamp: Time.current.iso8601
      }
    end
  end
end
