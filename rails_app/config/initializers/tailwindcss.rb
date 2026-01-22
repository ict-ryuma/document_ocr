# Disable Tailwind CSS default asset pipeline check
# We're using standalone Tailwind CSS binary instead
Rails.application.config.after_initialize do
  # Skip tailwindcss-rails asset pipeline integration
end
