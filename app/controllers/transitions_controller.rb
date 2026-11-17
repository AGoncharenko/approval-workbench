# Status changes on an invoice (submit, approve, reject). TransitionInvoice is authoritative; this maps its outcome to HTTP and a notice.
class TransitionsController < ApplicationController
  REFUSAL_STATUSES = { conflict: :conflict, forbidden: :forbidden, invalid: :unprocessable_content }.freeze

  def create
    input = params.fetch(:transition, {}).permit(:action, :expected_version, :idempotency_key, :reason)
    result = TransitionInvoice.call(actor: Current.user, invoice_uuid: params[:invoice_id], action: input[:action],
      expected_version: input[:expected_version], idempotency_key: input[:idempotency_key], reason: input[:reason])

    case result.outcome
    when :applied
      redirect_to invoice_path(params[:invoice_id]), status: :see_other, notice: t("approvals.outcomes.applied.#{input[:action]}")
    when :replayed
      redirect_to invoice_path(params[:invoice_id]), status: :see_other,
        flash: { info: outcome_t(input[:action], :replayed, time: l(result.event.created_at, format: :long)) }
    when :not_found
      raise ActiveRecord::RecordNotFound
    else
      render_refusal(result, input[:reason])
    end
  end

  private

  # Re-renders the invoice as it is now (re-read through the visibility scope), with the refusal explained.
  def render_refusal(result, reason)
    @invoice = InvoicePolicy::Scope.new(Current.user).resolve.find_by!(uuid: params[:invoice_id])
    @reason = reason
    @reason_error = t("approvals.errors.reason.#{result.errors[:reason]}") if result.errors[:reason]
    kind = result.outcome == :conflict ? :conflict : :alert
    flash.now[kind] = refusal_message(result, params.dig(:transition, :action))
    render "invoices/show", status: REFUSAL_STATUSES.fetch(result.outcome)
  end

  def refusal_message(result, action)
    case result.outcome
    when :forbidden then outcome_t(action, :forbidden)
    when :invalid then outcome_t(action, result.errors[:idempotency_key] == :reused ? :reused_key : :invalid)
    when :conflict
      status, version, event = helpers.invoice_status_label(@invoice.status), @invoice.version, result.event
      if event
        t("approvals.outcomes.conflict", status:, version:, actor: event.actor.name, time: l(event.created_at, format: :long))
      else
        t("approvals.outcomes.conflict_without_event", status:, version:)
      end
    end
  end

  # Submit has its own wording where the shared text speaks of a "decision"; everything else is shared.
  def outcome_t(action, key, **)
    shared = :"approvals.outcomes.#{key}"
    action == "submit" ? t("approvals.outcomes.submit.#{key}", default: shared, **) : t(shared, **)
  end
end
