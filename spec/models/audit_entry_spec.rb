require "rails_helper"

RSpec.describe AuditEntry do
  let(:company) { create(:company) }
  let(:approver) { create(:user, :approver, company:) }
  let(:admin) { create(:user, :admin, company:) }
  let(:invoice) { create(:invoice, :pending, company:) }

  let!(:approval_event) do
    ApprovalEvent.create!(company:, invoice:, actor: approver, actor_role: "approver", action: "reject",
      from_status: "PENDING", to_status: "REJECTED", reason: "No PO")
  end
  let!(:role_change_event) do
    RoleChangeEvent.create!(company:, actor: admin, target_user: approver, from_role: "approver", to_role: "requester")
  end

  it "lists both kinds of event with common columns" do
    rows = company.audit_entries.order(:kind).map do
      it.attributes.slice(*%w[kind company_id actor_id actor_role invoice_id target_user_id action from_value to_value reason source_id])
    end

    expect(rows).to eq([
      { "kind" => "role_change", "company_id" => company.id, "actor_id" => admin.id, "actor_role" => "admin", "invoice_id" => nil,
        "target_user_id" => approver.id, "action" => "role_change", "from_value" => "approver", "to_value" => "requester",
        "reason" => nil, "source_id" => role_change_event.id },
      { "kind" => "transition", "company_id" => company.id, "actor_id" => approver.id, "actor_role" => "approver",
        "invoice_id" => invoice.id, "target_user_id" => nil, "action" => "reject", "from_value" => "PENDING",
        "to_value" => "REJECTED", "reason" => "No PO", "source_id" => approval_event.id }
    ])
    expect(company.audit_entries.map(&:created_at)).to all(be_within(5.seconds).of(Time.current))
    expect(company.audit_entries.find_by(kind: "role_change")).to have_attributes(actor: admin, target_user: approver, invoice: nil)
  end

  it "raises on writes, through the model and in the database" do
    entry = described_class.take
    expect { entry.update!(reason: "x") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { described_class.create!(entry.attributes) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { ApplicationRecord.connection.execute("UPDATE audit_entries SET reason = 'x'") }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only|cannot update view/)
  end
end
