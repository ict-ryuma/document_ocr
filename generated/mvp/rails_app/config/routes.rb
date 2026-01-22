Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Estimates
  post "estimates/from_pdf", to: "estimates#from_pdf"
  get "estimates", to: "estimates#index"

  # Recommendations
  get "recommendations/by_item", to: "recommendations#by_item"

  # Kintone
  post "kintone/push", to: "kintone#push"

  # Natural Language
  get "nl/query", to: "nl#query"
end
