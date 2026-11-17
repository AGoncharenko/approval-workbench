require "rails_helper"

RSpec.describe "An admin revokes an approver's role", type: :system do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:, name: "Ada Admin") }
  let(:approver) { create(:user, :approver, company:, name: "Alex Approver") }
  let!(:invoice) { create(:invoice, :pending, company:, vendor_name: "Northwind Office Supply", version: 2) }

  it "refuses the approval from the approver's already-open page and records the change in the audit history" do
    using_session(:approver) do
      sign_in_through_ui(approver)
      visit invoice_path(invoice)
      expect(page).to have_button("Approve")
    end

    using_session(:admin) do
      sign_in_through_ui(admin)
      click_on "Users"
      select "Requester", from: "Role for Alex Approver"
      within("tr", text: "Alex Approver") { click_on "Save role" }
      expect(page).to have_css("#notice", text: "Alex Approver changed from Approver to Requester.")
    end

    using_session(:approver) do
      click_on "Approve"
      expect(page).to have_css("h1", text: "Invoice not available")
      expect(page).to have_text("isn't visible to your account")
    end
    expect(invoice.reload).to have_attributes(status: "pending", version: 2)

    using_session(:admin) do
      click_on "Audit history"
      expect(page).to have_css("tbody tr", count: 1)
      expect(page).to have_css("tbody tr", text: /Ada Admin \(admin\) Role change Alex Approver Approver →\s+to\s+Requester/)
    end
  end
end
