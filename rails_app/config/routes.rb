Rails.application.routes.draw do
  # Web UI routes
  root "estimates#new"

  resources :estimates, only: [ :index, :new, :create, :show ] do
    collection do
      post :confirm  # Save user-confirmed estimate data
      get :preview_file  # Preview uploaded PDF/image file
    end
  end

  # API endpoints (legacy support)
  post "/estimates/from_pdf", to: "estimates#from_pdf"
  post "/estimates/upload", to: "estimates#from_pdf_upload"

  # Recommendations endpoint
  get  "/recommendations/by_item", to: "recommendations#by_item"

  # Kintone endpoints
  post "/kintone/push", to: "kintone#push"
  get  "/kintone/health", to: "kintone#health"

  # Health check
  get "/health", to: "application#health"
end
