require "rails_helper"

RSpec.describe "Decisions whose response never arrives", type: :system do
  let(:company) { create(:company) }
  let(:approver) { create(:user, :approver, company:) }
  let!(:invoice) { create(:invoice, :pending, company:, vendor_name: "Flaky Network Vendor", version: 7) }

  before do
    sign_in_through_ui(approver)
    visit invoice_path(invoice)
  end

  it "says the outcome is unknown when the server committed but the response was lost, and Retry reports it already recorded" do
    DropResponse.mode = :after_app
    click_on "Approve"

    expect(page).to have_css("#notice", text: "Outcome not confirmed")
    expect(page).to have_no_css("#notice", text: /approved|rejected|not applied/i) # claims neither success nor failure
    expect(ApprovalEvent.where(invoice:).count).to eq(1) # it did commit on the server
    key = find("input[name='transition[idempotency_key]']", visible: false, match: :first).value

    DropResponse.mode = nil
    click_on "Retry"
    expect(page).to have_css("#notice", text: "Already recorded: this decision was saved at")
    expect(page).to have_css("dd", text: "Approved (not paid)")
    expect(ApprovalEvent.where(invoice:, action: "approve").count).to eq(1)
    expect(IdempotencyKey.sole.key).to eq(key) # the retry reused the same key
  end

  it "applies exactly once when the first attempt never reached the server" do
    DropResponse.mode = :before_app
    click_on "Approve"

    expect(page).to have_css("#notice", text: "Outcome not confirmed")
    expect(ApprovalEvent.count).to eq(0)

    DropResponse.mode = nil
    click_on "Retry"
    expect(page).to have_css("#notice", text: "Invoice approved.")
    expect(ApprovalEvent.where(invoice:).count).to eq(1)
  end

  it "shows the authoritative state after a reload, with no notice claiming success or failure" do
    DropResponse.mode = :after_app
    click_on "Approve"
    expect(page).to have_css("#notice", text: "Outcome not confirmed")

    DropResponse.mode = nil
    click_on "Reload"
    expect(page).to have_css("dd", text: "Approved (not paid)")
    expect(page).to have_css("section[aria-labelledby=history-heading] li", count: 1)
    expect(find("#notice").text).to be_empty
  end
end
