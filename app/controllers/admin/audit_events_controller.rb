# Company-wide audit history (invoice transitions and role changes), newest first.
class Admin::AuditEventsController < Admin::BaseController
  PER_PAGE = 50
  MAX_PAGE = 10_000 # keeps the offset far from bigint overflow on a forged page number

  def index
    @filter = AuditFilter.new(Current.company, params.permit(*AuditFilter::PARAMS))
    @page = params[:page].to_i.clamp(1, MAX_PAGE)
    rows = @filter.resolve.includes(:actor, :invoice, :target_user).order(created_at: :desc, source_id: :desc)
      .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @next_page = @page + 1 if rows.size > PER_PAGE
    @entries = rows.first(PER_PAGE)
    @users = Current.company.users.order(:name, :id)
  end
end
