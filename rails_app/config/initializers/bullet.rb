# Bullet configuration for N+1 query detection
# https://github.com/flyerhzm/bullet

if defined?(Bullet)
  Rails.application.configure do
    config.after_initialize do
      Bullet.enable = true
      Bullet.alert = false  # JavaScript alert in browser (disabled - too intrusive)
      Bullet.bullet_logger = true  # Log to log/bullet.log
      Bullet.console = true  # Browser console warnings
      Bullet.rails_logger = true  # Add warnings to Rails log
      Bullet.add_footer = true  # Add summary to page footer in development

      # Raise errors in test environment for CI
      Bullet.raise = Rails.env.test?

      # Detect N+1 queries
      Bullet.n_plus_one_query_enable = true

      # Detect unused eager loading
      Bullet.unused_eager_loading_enable = true

      # Detect counter cache recommendations
      Bullet.counter_cache_enable = true
    end
  end
end
