require "rails_helper"

RSpec.describe TransitionInvoice do
  let(:company) { create(:company) }
  let(:author) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }
  let(:invoice) { create(:invoice, :pending, company:, submitted_by: author, version: 7) }

  def run(actor: approver, uuid: invoice.uuid, action: "approve", expected_version: 7, key: SecureRandom.uuid, reason: nil)
    described_class.call(actor:, invoice_uuid: uuid, action:, expected_version:, idempotency_key: key, reason:)
  end

  def expect_unchanged(target = invoice)
    status, version = target.status, target.version
    expect(target.reload.status).to eq(status)
    expect(target.version).to eq(version)
    expect(ApprovalEvent.where(invoice: target)).to be_empty
    expect(IdempotencyKey.count).to eq(0)
  end

  it "approves a pending invoice, bumps the version and writes one event" do
    result = run
    expect(result.outcome).to eq(:applied)
    expect(invoice.reload).to have_attributes(status: "approved", version: 8)
    expect(result.event).to have_attributes(invoice:, company:, actor: approver, actor_role: "approver", action: "approve",
      from_status: "PENDING", to_status: "APPROVED", reason: nil)
    expect(IdempotencyKey.sole.approval_event).to eq(result.event)
  end

  it "rejects with a reason and stores it on the event" do
    result = run(action: "reject", reason: "  Duplicate of INV-1  ")
    expect(result.outcome).to eq(:applied)
    expect(invoice.reload.status).to eq("rejected")
    expect(result.event).to have_attributes(action: "reject", to_status: "REJECTED", reason: "Duplicate of INV-1")
  end

  it "refuses a rejection without a reason, or with one over 1000 characters" do
    expect(run(action: "reject", reason: "  ").to_h.slice(:outcome, :errors)).to eq(outcome: :invalid, errors: { reason: :blank })
    expect(run(action: "reject", reason: "x" * 1001).errors).to eq(reason: :too_long)
    expect_unchanged
  end

  it "reports a stale version as a conflict naming the latest actor" do
    first = run
    result = run(actor: create(:user, :approver, company:), action: "reject", reason: "No PO")
    expect(result.outcome).to eq(:conflict)
    expect(result.invoice).to have_attributes(status: "approved", version: 8)
    expect(result.event).to eq(first.event)
    expect(result.event.actor).to eq(approver)
    expect(ApprovalEvent.count).to eq(1)
  end

  it "reports a version mismatch as a conflict even while still pending" do
    expect(run(expected_version: 6).outcome).to eq(:conflict)
    expect_unchanged
  end

  it "reports an already decided invoice as a conflict" do
    decided = create(:invoice, :rejected, company:, submitted_by: author)
    result = run(uuid: decided.uuid, expected_version: decided.version)
    expect(result.outcome).to eq(:conflict)
    expect_unchanged(decided)
  end

  it "treats a draft as not found" do
    draft = create(:invoice, company:, submitted_by: author)
    expect(run(uuid: draft.uuid, expected_version: 1).outcome).to eq(:not_found)
    expect_unchanged(draft)
  end

  it "treats another company's invoice as not found" do
    foreign = create(:invoice, :pending, version: 7)
    expect(run(uuid: foreign.uuid).outcome).to eq(:not_found)
    expect_unchanged(foreign)
  end

  it "treats another requester's invoice as not found for a requester, even when also stale" do
    expect(run(actor: create(:user, company:), expected_version: 1).outcome).to eq(:not_found)
    expect_unchanged
  end

  it "forbids a requester on their own invoice, and an admin" do
    expect(run(actor: author).outcome).to eq(:forbidden)
    expect(run(actor: create(:user, :admin, company:)).outcome).to eq(:forbidden)
    expect_unchanged
  end

  it "forbids rather than conflicts when the actor may not act and the invoice is also stale" do
    expect(run(actor: create(:user, :admin, company:), expected_version: 1).outcome).to eq(:forbidden)
  end

  it "re-reads the actor's role: an approver demoted before the command no longer sees the invoice" do
    stale_actor = User.find(approver.id)
    User.where(id: approver.id).update_all(role: "requester")
    expect(run(actor: stale_actor).outcome).to eq(:not_found)
    expect_unchanged
  end

  it "forbids self-approval by an author later promoted to approver" do
    author.update!(role: "approver")
    expect(run(actor: author).outcome).to eq(:forbidden)
    expect_unchanged
  end

  it "replays the same key and payload without applying again" do
    first = run(key: "k-1")
    second = run(key: "k-1")
    expect(second.outcome).to eq(:replayed)
    expect(second.event).to eq(first.event)
    expect(invoice.reload.version).to eq(8)
    expect(ApprovalEvent.count).to eq(1)
  end

  it "refuses the same key with a different payload" do
    run(key: "k-1")
    result = run(key: "k-1", action: "reject", reason: "Changed my mind")
    expect(result.to_h.slice(:outcome, :errors)).to eq(outcome: :invalid, errors: { idempotency_key: :reused })
    expect(invoice.reload).to have_attributes(status: "approved", version: 8)
    expect(ApprovalEvent.count).to eq(1)
  end

  it "scopes keys to the actor, so another approver's identical key is a fresh command" do
    run(key: "k-1")
    expect(run(actor: create(:user, :approver, company:), key: "k-1").outcome).to eq(:conflict)
  end

  it "frees the key of a refused command, so a corrected retry is evaluated fresh" do
    expect(run(key: "k-1", expected_version: 6).outcome).to eq(:conflict)
    expect(run(key: "k-1").outcome).to eq(:applied)
  end

  it "refuses a missing key, a missing version and an unknown action" do
    expect(run(key: "").errors).to eq(idempotency_key: :blank)
    expect(run(key: "k" * 256).errors).to eq(idempotency_key: :too_long)
    expect(run(expected_version: "abc").errors).to eq(expected_version: :blank)
    expect(run(action: "submit").errors).to eq(action: :inclusion)
    expect_unchanged
  end

  describe "atomicity", :concurrency do
    # A real database failure on the audit insert, outside any test transaction, so commit/rollback is genuine.
    around do |example|
      conn = ActiveRecord::Base.connection
      conn.execute(<<~SQL)
        CREATE FUNCTION test_fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN RAISE EXCEPTION 'audit insert failed (test)'; END $$;
        CREATE TRIGGER test_fail_audit BEFORE INSERT ON approval_events FOR EACH ROW EXECUTE FUNCTION test_fail_audit();
      SQL
      example.run
    ensure
      conn.execute("DROP TRIGGER IF EXISTS test_fail_audit ON approval_events; DROP FUNCTION IF EXISTS test_fail_audit();")
    end

    it "leaves the invoice status and version unchanged when the event insert fails" do
      expect { run }.to raise_error(ActiveRecord::StatementInvalid, /audit insert failed/)
      expect(invoice.reload).to have_attributes(status: "pending", version: 7)
      expect(ApprovalEvent.count).to eq(0)
      expect(IdempotencyKey.count).to eq(0)
    end
  end
end
