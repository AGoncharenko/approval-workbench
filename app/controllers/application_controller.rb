class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Runs after require_authentication, so lines logged during the action name the signed-in user and company.
  around_action :tag_logs_with_actor

  # Missing, another company's and not-visible records all get this same response, so existence never leaks.
  rescue_from ActiveRecord::RecordNotFound do
    render "errors/not_found", status: :not_found
  end

  private
    # push/pop, not tagged { }: a BroadcastLogger with several sinks would run a tagged block, so the action, once per sink.
    def tag_logs_with_actor
      return yield unless Current.user

      logger.push_tags("user=#{Current.user.uuid}", "company=#{Current.company.uuid}")
      begin
        yield
      ensure
        logger.pop_tags(2)
      end
    end
end
