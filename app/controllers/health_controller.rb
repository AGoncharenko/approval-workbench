# Load balancer and uptime probe at /up. Inherits from ActionController::Base, not ApplicationController,
# so it needs no session, no browser check and no log tags; it returns a status code only.
class HealthController < ActionController::Base
  def show
    ActiveRecord::Base.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") }
    head :ok
  rescue ActiveRecord::ActiveRecordError
    head :service_unavailable
  end
end
