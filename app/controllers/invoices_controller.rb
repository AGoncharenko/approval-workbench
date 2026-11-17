class InvoicesController < ApplicationController
  PER_PAGE = 25
  MAX_PAGE = 10_000 # keeps the offset far from bigint overflow on a forged page number

  before_action :set_invoice, only: %i[ show edit update destroy ]
  before_action :require_create, only: %i[ new create ]
  before_action :require_update, only: %i[ edit update destroy ]

  def index
    @status = params[:status].to_s.downcase.presence_in(Invoice.statuses.keys)
    @page = params[:page].to_i.clamp(1, MAX_PAGE)

    invoices = visible_invoices.order(:due_date, :id)
    invoices = invoices.where(status: @status) if @status
    rows = invoices.limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @next_page = @page + 1 if rows.size > PER_PAGE
    @invoices = rows.first(PER_PAGE)
  end

  def show
  end

  def new
    @invoice = Current.company.invoices.new(currency: Money::CURRENCIES.first)
  end

  # Company and author come from the session only; a company_id in the body is not permitted.
  def create
    @invoice = Current.company.invoices.new(draft_params.merge(submitted_by: Current.user))
    if @invoice.save
      redirect_to @invoice, status: :see_other, notice: t("invoices.drafts.saved")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  # Applies only if the draft is still ours, still DRAFT and still at the version the form showed.
  def update
    # Kept for a re-rendered form, so fixing a field error can't silently skip the version check.
    @expected_version = Integer(params[:expected_version], 10, exception: false)
    @invoice.assign_attributes(draft_params)
    flash.now[:alert] = t("approvals.outcomes.invalid") unless @expected_version
    return render(:edit, status: :unprocessable_content) unless @invoice.valid? && @expected_version
    return redirect_to(@invoice, status: :see_other, notice: t("invoices.drafts.saved")) if save_draft

    set_invoice
    return unless require_update
    @expected_version = nil # the form now shows the current values and version
    flash.now[:conflict] = t("invoices.drafts.conflict", version: @invoice.version)
    render :edit, status: :conflict
  end

  # A hard delete: drafts have no audit events. Locked and re-checked as DRAFT, so a submit that commits first wins.
  def destroy
    discarded = Invoice.transaction { own_drafts.lock.find_by(id: @invoice.id)&.destroy! }
    if discarded
      redirect_to invoices_path, status: :see_other, notice: t("invoices.drafts.discarded", vendor: @invoice.vendor_name)
    else
      set_invoice
      require_update
    end
  end

  private

  def visible_invoices = InvoicePolicy::Scope.new(Current.user).resolve

  def own_drafts = Current.company.invoices.draft.where(submitted_by: Current.user)

  # Locked so the version check and the write can't interleave with a concurrent submit or edit.
  # Returns nil when the draft is no longer ours, no longer DRAFT or no longer at the expected version.
  def save_draft
    Invoice.transaction do
      own_drafts.lock.find_by(id: @invoice.id, version: @expected_version)
        &.update!(draft_params.merge(version: @expected_version + 1))
    end
  end

  # Not visible (another company's, someone else's draft, missing) is a 404 via ApplicationController.
  def set_invoice
    @invoice = visible_invoices.find_by!(uuid: params[:id])
  end

  def require_create = authorize(InvoicePolicy.new(Current.user, Invoice.new).create?)

  def require_update = authorize(InvoicePolicy.new(Current.user, @invoice).update?)

  # Visible but not allowed: 403. Returns whether the action may continue.
  def authorize(allowed)
    render "errors/forbidden", status: :forbidden unless allowed
    allowed
  end

  def draft_params = params.fetch(:invoice, {}).permit(:vendor_name, :amount, :currency, :due_date)
end
