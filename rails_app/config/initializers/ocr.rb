# OCR Service Configuration
#
# This initializer configures the OCR adapters for PDF parsing.
# The system uses a 3-tier fallback strategy:
#   1. GPT-4o Vision (Primary) - Azure OpenAI
#   2. Document AI (Fallback) - Google Cloud
#   3. Dummy (Development/Test)

Rails.application.config.ocr = ActiveSupport::OrderedOptions.new

# Azure OpenAI Configuration (existing ENV variables)
Rails.application.config.ocr.azure = {
  api_key: ENV["AZURE_OPENAI_API_KEY"],
  endpoint: ENV["AZURE_OPENAI_ENDPOINT"],
  deployment_name: ENV.fetch("AZURE_DEPLOYMENT_NAME", "gpt-4o"),
  api_version: ENV.fetch("AZURE_API_VERSION", "2024-12-01-preview")
}.freeze

# Google Document AI Configuration
Rails.application.config.ocr.document_ai = {
  project_id: ENV["GCP_PROJECT_ID"],
  processor_id: ENV["DOCUMENT_AI_PROCESSOR_ID"],
  location: ENV.fetch("DOCUMENT_AI_LOCATION", "us"),
  credentials_path: ENV["GOOGLE_APPLICATION_CREDENTIALS"]
}.freeze

# Timeouts (in seconds)
Rails.application.config.ocr.timeouts = {
  vision_api: 60,
  document_ai: 120,
  pdf_conversion: 30
}.freeze

# Image conversion settings
Rails.application.config.ocr.image = {
  max_dimension: 2048,
  dpi: 200,
  quality: 95,
  format: "jpeg"
}.freeze
