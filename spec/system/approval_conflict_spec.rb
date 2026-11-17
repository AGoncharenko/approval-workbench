require "rails_helper"

RSpec.describe "Two approvers decide on the same invoice", type: :system do
  let(:company) { create(:company) }
  let(:alice) { create(:user, :approver, company:, name: "Alice Approver") }
  let(:bob) { create(:user, :approver, company:, name: "Bob Approver") }
  let!(:invoice) { create(:invoice, :pending, company:, vendor_name: "Contested Vendor", version: 7) }

  it "applies the first decision and shows the second approver a conflict with the current state" do
    using_session(:bob) do
      sign_in_through_ui(bob)
      visit invoice_path(invoice)
      fill_in "Reason for rejection (required)", with: "No purchase order"
    end

    using_session(:alice) do
      sign_in_through_ui(alice)
      visit invoice_path(invoice)
      click_on "Approve"
      expect(page).to have_css("#notice", text: "Invoice approved.")
      expect(page).to have_css("section[aria-labelledby=history-heading] li", text: "Approved by Alice Approver (approver)")
    end

    using_session(:bob) do
      click_on "Reject"
      expect(page).to have_css("#notice", text: /Not applied: this invoice changed since you opened it\. It is now Approved \(not paid\) \(version 8\), last changed by Alice Approver at/)
      expect(page).to have_no_button("Reject") # controls reflect the current state
      expect(page).to have_css("dd", text: "Approved (not paid)")
    end

    expect(invoice.reload).to have_attributes(status: "approved", version: 8)
    expect(ApprovalEvent.where(invoice:).count).to eq(1)
  end
end
