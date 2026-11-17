class InvoicesController < ApplicationController
  PER_PAGE = 25
  MAX_PAGE = 10_000 # keeps the offset far from bigint overflow on a forged page number

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
    @invoice = visible_invoices.find_by!(uuid: params[:id])
  end

  private
    def visible_invoices = InvoicePolicy::Scope.new(Current.user).resolve
end
