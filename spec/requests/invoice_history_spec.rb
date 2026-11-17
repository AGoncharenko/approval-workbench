require "rails_helper"

RSpec.describe "Per-invoice history" do
  before { Rails.application.load_seed }

  it "shows an approver the submit and approve events of an approved seeded invoice, in order, with actor and time" do
    post session_path, params: { email_address: "approver2@acme.example.com", password: "demo-password-2026" }
    invoice = Invoice.find_by!(vendor_name: "Blue Harbor Logistics")
    expect(invoice.status).to eq("approved")

    get invoice_path(invoice)
    items = Nokogiri::HTML(response.body).css("section[aria-labelledby=history-heading] ol li")
    expect(items.map { it.at_css("p").text.squish.sub(/ · .*/, "") })
      .to eq([ "Submitted by Rita Requester (requester)", "Approved by Alex Approver (approver)" ])
    expect(items.map { it.at_css("time")["datetime"] }).to eq(invoice.approval_events.order(:created_at, :id).map { it.created_at.iso8601 })
  end
end
