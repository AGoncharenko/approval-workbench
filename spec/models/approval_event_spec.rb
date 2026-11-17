require "rails_helper"

RSpec.describe ApprovalEvent do
  let(:invoice) { create(:invoice, :pending) }
  let(:approver) { create(:user, :approver, company: invoice.company) }

  def event_attributes(**overrides)
    { company: invoice.company, invoice:, actor: approver, actor_role: "approver", action: "approve",
      from_status: "PENDING", to_status: "APPROVED" }.merge(overrides)
  end

  it "records an event with a server timestamp" do
    event = described_class.create!(event_attributes)
    expect(event.reload.created_at).to be_within(5.seconds).of(Time.current)
  end

  it "is rejected by the database when it points at another company's invoice" do
    foreign_invoice = create(:invoice, :pending)
    expect {
      described_class.create!(event_attributes(invoice: foreign_invoice)) # company stays the approver's
    }.to raise_error(ActiveRecord::InvalidForeignKey, /approval_events_invoice_same_company/)
  end

  it "is rejected by the database for an unknown action or status" do
    expect { described_class.create!(event_attributes(action: "pay")) }.to raise_error(ActiveRecord::StatementInvalid, /action_allowed/)
    expect { described_class.create!(event_attributes(to_status: "PAID")) }.to raise_error(ActiveRecord::StatementInvalid, /to_status_allowed/)
  end

  it "keeps users with history from being deleted" do
    described_class.create!(event_attributes)
    expect { approver.delete }.to raise_error(ActiveRecord::StatementInvalid, /RestrictViolation/)
  end

  it "cannot be updated or destroyed through the model" do
    event = described_class.create!(event_attributes)
    expect { event.update!(reason: "changed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
