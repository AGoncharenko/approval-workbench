# The one command that changes an invoice's status. Returns a Result whose outcome is one of
# :applied, :replayed, :conflict, :forbidden, :not_found or :invalid. Only :applied writes anything:
# every other outcome rolls the transaction back, including the claimed idempotency key.
class TransitionInvoice
  REASON_MAX = 1000
  KEY_MAX = 255

  Result = Data.define(:outcome, :invoice, :event, :errors) do
    def self.of(outcome, invoice: nil, event: nil, errors: {}) = new(outcome:, invoice:, event:, errors:)
  end

  def self.call(...) = new(...).call

  def initialize(actor:, invoice_uuid:, action:, expected_version:, idempotency_key:, reason: nil)
    @actor = actor
    @invoice_uuid = invoice_uuid.to_s
    @action = action.to_s
    @expected_version = Integer(expected_version.to_s, 10, exception: false) # base 10: "010" is not octal, "0x10" not hex
    @key = idempotency_key.to_s
    @reason = reason.to_s.strip.presence
  end

  def call
    errors = validation_errors
    return Result.of(:invalid, errors:) if errors.any?

    result = nil
    ApplicationRecord.transaction do
      result = decide
      raise ActiveRecord::Rollback unless result.outcome == :applied
    end
    result
  end

  private
    # Request-shape checks only: they read no invoice, so a 422 here can't reveal whether one exists.
    def validation_errors
      errors = {}
      errors[:idempotency_key] = :blank if @key.blank?
      errors[:idempotency_key] = :too_long if @key.length > KEY_MAX
      errors[:action] = :inclusion unless InvoicePolicy::TRANSITIONS.key?(@action)
      errors[:expected_version] = :blank unless @expected_version
      errors[:reason] = :blank if @action == "reject" && @reason.nil?
      errors[:reason] = :too_long if @reason && @reason.length > REASON_MAX
      errors
    end

    def decide
      key_id = claim_key
      return replay unless key_id

      actor = User.lock("FOR SHARE").find(@actor.id) # current role; a role change waits until we commit
      invoice = InvoicePolicy::Scope.new(actor).resolve.lock.find_by(uuid: @invoice_uuid)
      return Result.of(:not_found) unless invoice

      policy = InvoicePolicy.new(actor, invoice)
      return Result.of(:forbidden, invoice:) unless policy.permitted?(@action)
      unless policy.transition?(@action) && invoice.version == @expected_version
        return Result.of(:conflict, invoice:, event: invoice.approval_history.last)
      end

      event = apply(invoice, actor)
      IdempotencyKey.where(id: key_id).update_all(approval_event_id: event.id)
      Result.of(:applied, invoice:, event:)
    end

    def apply(invoice, actor)
      from_status = Invoice.statuses.fetch(invoice.status)
      invoice.update!(status: InvoicePolicy::TRANSITIONS.fetch(@action)[:to], version: invoice.version + 1)
      invoice.approval_events.create!(company_id: invoice.company_id, actor:, actor_role: actor.role, action: @action,
        from_status:, to_status: Invoice.statuses.fetch(invoice.status), reason: @reason)
    end

    # INSERT ... ON CONFLICT DO NOTHING RETURNING id. If another transaction holds the same key uncommitted,
    # this blocks on the unique index until it commits (no row back: replay) or aborts (we claim it).
    def claim_key
      IdempotencyKey.insert(key_scope.merge(fingerprint:), unique_by: %i[company_id user_id key], returning: :id).rows.dig(0, 0)
    end

    def replay
      stored = IdempotencyKey.find_by!(key_scope)
      return Result.of(:invalid, errors: { idempotency_key: :reused }) unless stored.fingerprint == fingerprint

      event = stored.approval_event
      Result.of(:replayed, invoice: event.invoice, event:)
    end

    def key_scope = { company_id: @actor.company_id, user_id: @actor.id, key: @key }

    def fingerprint
      @fingerprint ||= Digest::SHA256.hexdigest([ @action, @invoice_uuid, @expected_version, @reason ].join("|"))
    end
end
