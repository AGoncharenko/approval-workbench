require "rails_helper"

# Real threads on separate connections. The main thread holds the company row lock while both commands start,
# waits until Postgres reports both sessions blocked on a lock, then releases it, so the two genuinely contend.
RSpec.describe ChangeUserRole, :concurrency do
  let(:company) { create(:company) }
  let!(:ada) { create(:user, :admin, company:) }
  let!(:ben) { create(:user, :admin, company:) }

  # Built on the main thread: RSpec's memoized lets must not be touched from the worker threads.
  def command(actor, target)
    args = { actor: User.find(actor.id), user_uuid: target.uuid, role: "requester" }
    -> { described_class.call(**args) }
  end

  # Statistics views are snapshotted per transaction, so clear the snapshot on every poll.
  def blocked_sessions
    ActiveRecord::Base.connection.execute("SELECT pg_stat_clear_snapshot()")
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    )
  end

  it "applies exactly one of two admins demoting each other, and the company keeps one admin" do
    threads = nil
    ActiveRecord::Base.transaction do
      Company.lock.find(company.id)
      threads = [ command(ada, ben), command(ben, ada) ].map do |cmd|
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { cmd.call } }
      end
      deadline = 5.seconds.from_now
      sleep 0.01 until blocked_sessions == 2 || Time.current > deadline
      expect(blocked_sessions).to eq(2)
    end
    outcomes = threads.map(&:value).map(&:outcome)

    expect(outcomes).to contain_exactly(:applied, :invalid)
    expect(company.users.admin.count).to eq(1)
    expect(RoleChangeEvent.count).to eq(1)
  end
end
