require "rails_helper"

RSpec.describe "Invoice submission", type: :system do
  let(:company) { create(:company) }
  let(:requester) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }

  it "lets a requester create and submit a draft, which an approver then sees as pending" do
    sign_in_through_ui(requester)
    click_on "New invoice"
    fill_in "Vendor", with: "Submitted End To End"
    fill_in "Amount", with: "10.005"
    select "USD", from: "Currency"
    fill_in "Due date", with: Date.current + 10
    click_on "Save draft"
    expect(page).to have_text("Amount must be a number of 0 or more with at most 2 decimal places for USD")

    fill_in "Amount", with: "1,234.56"
    click_on "Save draft"
    expect(page).to have_css("#notice", text: "Draft saved.")
    expect(page).to have_css("dd", text: "USD 1,234.56")
    expect(page).to have_css("dd", text: "Draft")

    click_on "Submit for approval"
    expect(page).to have_css("#notice", text: "Invoice submitted for approval.")
    expect(page).to have_css("dd", text: "Pending approval")
    expect(page).to have_no_button("Submit for approval")
    expect(page).to have_no_link("Edit draft")
    expect(page).to have_css("section[aria-labelledby=history-heading] li", text: "Submitted by #{requester.name}")

    click_on "Sign out"
    sign_in_through_ui(approver)
    within("tbody") { expect(page).to have_css("tr", text: /Submitted End To End.*USD 1,234.56.*Pending approval/m) }
    click_on "Submitted End To End"
    expect(page).to have_button("Approve")
  end
end
