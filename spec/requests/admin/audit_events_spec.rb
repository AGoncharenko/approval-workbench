require "rails_helper"

RSpec.describe "Admin audit history" do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:, name: "Ada Admin") }
  let(:alice) { create(:user, :approver, company:, name: "Alice Approver") }
  let(:invoice) { create(:invoice, :pending, company:, vendor_name: "Northwind") }
  let(:foreign_invoice) { create(:invoice, :pending, vendor_name: "Foreign Vendor") }

  def event(actor, invoice, action, at:, reason: nil)
    ApprovalEvent.create!(company: invoice.company, invoice:, actor:, actor_role: actor.role, action:, created_at: at,
      from_status: "PENDING", to_status: action == "approve" ? "APPROVED" : "REJECTED", reason:)
  end

  def rows = Nokogiri::HTML(response.body).css("tbody tr").map { it.css("td").map { |td| td.text.squish } }

  before { sign_in_as admin }

  it "lists own-company transitions and role changes newest first, with time, actor, role, action, change and reason" do
    rejected = event(alice, invoice, "reject", at: Time.utc(2026, 11, 1, 9, 30), reason: "No PO")
    event(create(:user, :approver, company: foreign_invoice.company), foreign_invoice, "approve", at: Time.utc(2026, 11, 1, 10))
    patch admin_user_path(alice), params: { user: { role: "requester" } }

    get admin_audit_events_path
    expect(response).to have_http_status(:ok)
    expect(rows.size).to eq(2)
    expect(rows.first).to eq([ I18n.l(RoleChangeEvent.sole.created_at, format: :long), "Ada Admin (admin)", "Role change",
      "Alice Approver", "Approver → to Requester", "" ])
    expect(rows.last).to eq([ "November 1, 2026 09:30 UTC", "Alice Approver (approver)", "Rejected", "Northwind",
      "Pending approval → to Rejected", "No PO" ])
    expect(Nokogiri::HTML(response.body).css("tbody time").last["datetime"]).to eq(rejected.created_at.iso8601)
    expect(response.body).not_to include("Foreign Vendor")
  end

  it "shows the actor's role at the time, after their role has changed" do
    event(alice, invoice, "approve", at: 1.hour.ago)
    alice.update!(role: "requester")

    get admin_audit_events_path
    expect(rows.sole[1]).to eq("Alice Approver (approver)")
  end

  it "filters by actor and action" do
    event(alice, invoice, "reject", at: 2.hours.ago, reason: "No PO")
    event(alice, create(:invoice, :pending, company:), "approve", at: 1.hour.ago)
    event(create(:user, :approver, company:), invoice, "reject", at: 1.hour.ago, reason: "Duplicate")

    get admin_audit_events_path, params: { actor: alice.uuid, event: "reject" }
    expect(rows.map { it.values_at(1, 2, 5) }).to eq([ [ "Alice Approver (approver)", "Rejected", "No PO" ] ])
  end

  it "paginates 50 per page, keeping the filters in the page links" do
    51.times { |i| event(alice, invoice, "approve", at: Time.utc(2026, 11, 1) + i.minutes) }

    get admin_audit_events_path, params: { event: "approve" }
    expect(rows.size).to eq(50)
    expect(rows.first.first).to eq("November 1, 2026 00:50 UTC")
    next_link = Nokogiri::HTML(response.body).at_css("nav[aria-label=Pagination] a")
    expect(next_link.text).to eq("Next page")

    get next_link["href"]
    expect(rows.map(&:first)).to eq([ "November 1, 2026 00:00 UTC" ])
  end
end
