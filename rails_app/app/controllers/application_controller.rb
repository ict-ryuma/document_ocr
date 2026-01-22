class ApplicationController < ActionController::Base
  def health
    # Check Django connection
    django_parser = DjangoPdfParser.new
    django_health = django_parser.health_check

    # Check database connection
    db_healthy = ActiveRecord::Base.connection.active? rescue false

    # Overall health status
    healthy = django_health[:status] == 'healthy' && db_healthy

    render json: {
      status: healthy ? 'healthy' : 'degraded',
      services: {
        rails: {
          status: 'healthy',
          database: db_healthy ? 'connected' : 'disconnected'
        },
        django: django_health
      },
      timestamp: Time.now.iso8601
    }
  end
end
