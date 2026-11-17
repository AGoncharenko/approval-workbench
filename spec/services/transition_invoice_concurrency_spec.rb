require "rails_helper"

# Real threads on separate database connections. To make the race deterministic, the main thread holds the
# invoice row lock while both commands start, waits until Postgres reports both sessions blocked on a lock,
# then releases it: the two commands genuinely contend instead of merely running one after the other.
RSpec.describe TransitionInvoice, :concurrency do
  let(:company) { create(:company) }
  let!(:invoice) { create(:invoice, :pending, company:, version: 7) }
  let!(:alice) { create(:user, :approver, company:) }
  let!(:bob) { create(:user, :approver, company:) }

  # Built on the main thread: RSpec's memoized lets must not be touched from the worker threads.
  def command(actor, key, action: "approve", reason: nil)
    args = { actor:, invoice_uuid: invoice.uuid, action:, expected_version: 7, idempotency_key: key, reason: }
    -> { described_class.call(**args) }
  end

  # Statistics views are snapshotted per transaction, so clear the snapshot on every poll.
  def blocked_sessions
    ActiveRecord::Base.connection.execute("SELECT pg_stat_clear_snapshot()")
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    )
  end

  def race(*commands)
    threads = nil
    ActiveRecord::Base.transaction do
      Invoice.lock.find(invoice.id)
      threads = commands.map { |cmd| Thread.new { ActiveRecord::Base.connection_pool.with_connection { cmd.call } } }
      deadline = 5.seconds.from_now
      sleep 0.01 until blocked_sessions == commands.size || Time.current > deadline
      expect(blocked_sessions).to eq(commands.size)
    end
    threads.map(&:value).map(&:outcome)
  end

  it "applies exactly one of two decisions on the same version and reports the other as a conflict" do
    outcomes = race(command(alice, "alice-key"), command(bob, "bob-key", action: "reject", reason: "No PO"))

    expect(outcomes).to contain_exactly(:applied, :conflict)
    expect(ApprovalEvent.where(invoice:).count).to eq(1)
    expect(invoice.reload.version).to eq(8)
    expect(IdempotencyKey.count).to eq(1)
  end

  it "applies one of two identical requests with the same key and replays the other" do
    outcomes = race(command(alice, "same-key"), command(alice, "same-key"))

    expect(outcomes).to contain_exactly(:applied, :replayed)
    expect(ApprovalEvent.where(invoice:).count).to eq(1)
    expect(invoice.reload).to have_attributes(status: "approved", version: 8)
  end
end
