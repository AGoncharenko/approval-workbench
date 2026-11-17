class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Missing, another company's and not-visible records all get this same response, so existence never leaks.
  rescue_from ActiveRecord::RecordNotFound do
    render "errors/not_found", status: :not_found
  end
end
