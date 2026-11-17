# The company's users, each row with an inline role form. ChangeUserRole is authoritative; this maps its outcome to HTTP.
class Admin::UsersController < Admin::BaseController
  REFUSAL_STATUSES = { forbidden: :forbidden, invalid: :unprocessable_content }.freeze

  def index
    @users = company_users
  end

  # Only the role is read; company, name and email in the body are ignored.
  def update
    role = params.require(:user).permit(:role)[:role]
    result = ChangeUserRole.call(actor: Current.user, user_uuid: params[:id], role:)
    user = result.user

    case result.outcome
    when :applied
      redirect_to admin_users_path, status: :see_other,
        notice: t("admin.users.changed", name: user.name, from: role_label(result.from_role), to: role_label(user.role))
    when :unchanged
      redirect_to admin_users_path, status: :see_other, flash: { info: t("admin.users.unchanged", name: user.name, role: role_label(user.role)) }
    when :not_found
      render "errors/not_found", status: :not_found,
        locals: { heading: t("admin.users.not_found.heading"), message: t("admin.users.not_found.message") }
    else
      @users = company_users
      if result.outcome == :forbidden
        flash.now[:alert] = t("admin.users.forbidden")
      else
        @row_errors = { user.uuid => t("admin.users.errors.#{result.error}") }
      end
      render :index, status: REFUSAL_STATUSES.fetch(result.outcome)
    end
  end

  private

  def company_users = Current.company.users.order(:name, :id)

  def role_label(role) = helpers.user_role_label(role)
end
