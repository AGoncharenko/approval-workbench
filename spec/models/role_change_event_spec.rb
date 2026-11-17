require "rails_helper"

RSpec.describe RoleChangeEvent do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:) }
  let(:target) { create(:user, :approver, company:) }

  def event_attributes(**overrides)
    { company:, actor: admin, target_user: target, from_role: "approver", to_role: "requester" }.merge(overrides)
  end

  # A savepoint, so the refused statement doesn't abort the example's transaction.
  def in_savepoint(&) = ApplicationRecord.transaction(requires_new: true, &)

  it "records an event with a server timestamp" do
    event = described_class.create!(event_attributes)
    expect(event.reload.created_at).to be_within(5.seconds).of(Time.current)
  end

  it "is rejected by the database when the target is in another company" do
    foreign_user = create(:user, :approver)
    expect { described_class.create!(event_attributes(target_user: foreign_user)) }
      .to raise_error(ActiveRecord::InvalidForeignKey, /role_change_events_target_same_company/)
  end

  it "is rejected by the database when the actor is in another company" do
    expect { described_class.create!(event_attributes(actor: create(:user, :admin))) }
      .to raise_error(ActiveRecord::InvalidForeignKey, /role_change_events_actor_same_company/)
  end

  it "is rejected by the database for an unknown or unchanged role" do
    expect { in_savepoint { described_class.create!(event_attributes(to_role: "owner")) } }.to raise_error(ActiveRecord::StatementInvalid, /to_role_allowed/)
    expect { in_savepoint { described_class.create!(event_attributes(to_role: "approver")) } }.to raise_error(ActiveRecord::StatementInvalid, /role_changed/)
  end

  it "is read-only through the model once created" do
    event = described_class.create!(event_attributes)
    expect { event.update!(to_role: "admin") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  describe "users with history" do
    let(:invoice) { create(:invoice, :pending, company:) }

    it "can't be deleted while they acted in or were the target of a role change, and the history stays" do
      event = described_class.create!(event_attributes)
      [ admin, target ].each do |user|
        expect { in_savepoint { user.delete } }.to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation.*role_change_events/m)
      end
      expect(described_class.find(event.id)).to have_attributes(actor_id: admin.id, target_user_id: target.id)
      expect(User.where(id: [ admin.id, target.id ]).count).to eq(2)
    end

    it "can't be deleted while they have an approval event, and the history stays" do
      approver = create(:user, :approver, company:)
      event = ApprovalEvent.create!(company:, invoice:, actor: approver, actor_role: "approver", action: "approve",
        from_status: "PENDING", to_status: "APPROVED")
      expect { in_savepoint { approver.destroy } }.to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation/)
      expect(ApprovalEvent.find(event.id).actor).to eq(approver)
    end
  end
end
