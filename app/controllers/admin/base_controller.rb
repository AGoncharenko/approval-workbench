# Every admin page inherits this, so none can forget the check. Current.user is re-read from the database per request.
# A non-admin gets 403, not 404: the admin pages' existence isn't secret.
class Admin::BaseController < ApplicationController
  before_action :require_admin

  private

  def require_admin
    render "errors/forbidden", status: :forbidden, locals: { message: t("admin.forbidden") } unless Current.user.admin?
  end
end
