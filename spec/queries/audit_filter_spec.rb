require "rails_helper"

RSpec.describe AuditFilter do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:) }
  let(:alice) { create(:user, :approver, company:) }
  let(:bob) { create(:user, :approver, company:) }
  let(:invoice_one) { create(:invoice, :pending, company:) }
  let(:invoice_two) { create(:invoice, :pending, company:) }

  let(:other_company) { create(:company) }
  let(:foreign_approver) { create(:user, :approver, company: other_company) }
  let(:foreign_invoice) { create(:invoice, :pending, company: other_company) }

  def event(actor, invoice, action, at:)
    to = { "approve" => "APPROVED", "reject" => "REJECTED", "submit" => "PENDING" }.fetch(action)
    ApprovalEvent.create!(company: invoice.company, invoice:, actor:, actor_role: actor.role, action:, created_at: at,
      from_status: action == "submit" ? "DRAFT" : "PENDING", to_status: to, reason: ("No PO" if action == "reject"))
  end

  let!(:alice_rejects_one) { event(alice, invoice_one, "reject", at: Time.utc(2026, 11, 1, 9)) }
  let!(:alice_approves_two) { event(alice, invoice_two, "approve", at: Time.utc(2026, 11, 2, 9)) }
  let!(:bob_rejects_two) { event(bob, invoice_two, "reject", at: Time.utc(2026, 11, 3, 23, 59)) }
  let!(:role_change) do
    RoleChangeEvent.create!(company:, actor: admin, target_user: bob, from_role: "approver", to_role: "requester", created_at: Time.utc(2026, 11, 4, 0, 0))
  end
  let!(:foreign_event) { event(foreign_approver, foreign_invoice, "reject", at: Time.utc(2026, 11, 2, 12)) }

  def filtered(**params) = described_class.new(company, params).resolve.map { [ it.kind, it.source_id ] }

  def transitions(*events) = events.map { [ "transition", it.id ] }

  it "lists every own-company event, both kinds, and nothing from another company" do
    expect(filtered).to contain_exactly(*transitions(alice_rejects_one, alice_approves_two, bob_rejects_two), [ "role_change", role_change.id ])
  end

  it "filters by action" do
    expect(filtered(event: "reject")).to contain_exactly(*transitions(alice_rejects_one, bob_rejects_two))
  end

  it "filters by event type" do
    expect(filtered(event: "role_change")).to eq([ [ "role_change", role_change.id ] ])
    expect(filtered(event: "transition")).to contain_exactly(*transitions(alice_rejects_one, alice_approves_two, bob_rejects_two))
  end

  it "ignores an unknown event type rather than matching nothing or erroring" do
    expect(filtered(event: "pay").size).to eq(4)
  end

  it "filters by actor and action together" do
    expect(filtered(actor: alice.uuid, event: "reject")).to eq(transitions(alice_rejects_one))
    expect(filtered(actor: admin.uuid)).to eq([ [ "role_change", role_change.id ] ])
  end

  it "filters by invoice" do
    expect(filtered(invoice: invoice_two.uuid)).to contain_exactly(*transitions(alice_approves_two, bob_rejects_two))
  end

  it "filters by an inclusive UTC date range" do
    expect(filtered(from: "2026-11-02", to: "2026-11-03")).to contain_exactly(*transitions(alice_approves_two, bob_rejects_two))
    expect(filtered(from: "2026-11-04")).to eq([ [ "role_change", role_change.id ] ])
    expect(filtered(to: "2026-11-01")).to eq(transitions(alice_rejects_one))
  end

  it "ignores malformed dates" do
    expect(filtered(from: "yesterday", to: "2026-13-45").size).to eq(4)
  end

  it "returns nothing for another company's actor or invoice UUID, or a malformed one" do
    expect(filtered(actor: foreign_approver.uuid)).to be_empty
    expect(filtered(invoice: foreign_invoice.uuid)).to be_empty
    expect(filtered(invoice: "not-a-uuid")).to be_empty
    expect(filtered(actor: SecureRandom.uuid)).to be_empty
  end
end
