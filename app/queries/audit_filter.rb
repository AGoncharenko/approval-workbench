# Filters a company's audit history. Every identifier is matched only inside that company,
# so a forged or unknown UUID (or one from another company) gives an empty result, never an error or a leak.
class AuditFilter
  ACTIONS = InvoicePolicy::TRANSITIONS.keys.freeze
  PARAMS = %i[event actor invoice from to].freeze

  attr_reader :event, :actor, :invoice, :from, :to

  def initialize(company, params = {})
    @company = company
    @event = params[:event].to_s.presence_in(AuditEntry::KINDS + ACTIONS)
    @actor = params[:actor].to_s.presence
    @invoice = params[:invoice].to_s.strip.presence
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])
  end

  def resolve
    entries = @company.audit_entries
    entries = entries.where(@event.in?(ACTIONS) ? { action: @event } : { kind: @event }) if @event
    entries = entries.where(actor_id: @company.users.where(uuid: @actor).select(:id)) if @actor
    entries = entries.where(invoice_id: @company.invoices.where(uuid: @invoice).select(:id)) if @invoice
    entries = entries.where(created_at: @from.beginning_of_day..) if @from
    entries = entries.where(created_at: ...@to.next_day.beginning_of_day) if @to
    entries
  end

  # The applied filters, for pagination links.
  def to_h = { event:, actor:, invoice:, from: from&.iso8601, to: to&.iso8601 }.compact

  private

  def parse_date(value) = Date.iso8601(value.to_s) rescue nil
end
