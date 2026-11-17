require "rails_helper"

RSpec.describe "Open pages refresh when an invoice changes", type: :system do
  let(:company) { create(:company) }
  let(:alice) { create(:user, :approver, company:, name: "Alice Approver") }
  let(:bob) { create(:user, :approver, company:, name: "Bob Approver") }
  let!(:invoice) { create(:invoice, :pending, company:, vendor_name: "Live Vendor", version: 4) }

  def open_as(user, path)
    sign_in_through_ui(user)
    visit path
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all) # subscribed before anything changes
  end

  def approve_as_alice
    using_session(:alice) do
      open_as(alice, invoice_path(invoice))
      click_on "Approve"
      expect(page).to have_css("#notice", text: "Invoice approved.")
    end
  end

  it "shows another approver's decision without a reload, and withdraws the controls" do
    using_session(:bob) { open_as(bob, invoice_path(invoice)) }
    approve_as_alice

    using_session(:bob) do
      expect(page).to have_css("dd", text: "Approved (not paid)")
      expect(page).to have_css("dd", text: "5")
      expect(page).to have_css("section[aria-labelledby=history-heading] li", count: 1, text: "Approved by Alice Approver (approver)")
      expect(page).to have_no_button("Approve")
      expect(page).to have_no_button("Reject")
      expect(find("#notice").text).to be_empty # a refresh is not a command outcome
    end
  end

  it "keeps a reason being typed, and a stale submit reports the conflict" do
    using_session(:bob) do
      open_as(bob, invoice_path(invoice))
      fill_in "Reason for rejection (required)", with: "No purchase order"
    end
    approve_as_alice

    using_session(:bob) do
      expect(page).to have_css("dd", text: "Approved (not paid)") # refreshed above the form
      expect(page).to have_field("Reason for rejection (required)", with: "No purchase order")
      expect(find("input[name='transition[expected_version]']", visible: false, match: :first).value).to eq("4") # the version Bob reviewed

      click_on "Reject"
      expect(page).to have_css("#notice", text: /Not applied: this invoice changed since you opened it\. It is now Approved \(not paid\) \(version 5\), last changed by Alice Approver/)
      expect(page).to have_no_button("Reject")
    end

    expect(invoice.reload).to have_attributes(status: "approved", version: 5)
    expect(ApprovalEvent.where(invoice:).count).to eq(1)
  end

  it "keeps the reason, version and key the user reviewed when the invoice changes but stays open" do
    using_session(:bob) do
      open_as(bob, invoice_path(invoice))
      fill_in "Reason for rejection (required)", with: "Wrong amount"
      @keys = all("input[name='transition[idempotency_key]']", visible: false).map(&:value)
    end
    invoice.update!(vendor_name: "Renamed Vendor", version: 5) # a change that leaves the controls in place

    using_session(:bob) do
      expect(page).to have_css("h1", text: "Renamed Vendor")
      expect(page).to have_field("Reason for rejection (required)", with: "Wrong amount")
      expect(all("input[name='transition[expected_version]']", visible: false).map(&:value)).to eq(%w[4 4])
      expect(page).to have_text("You are deciding on version 4.") # the page states the version the buttons act on
      expect(all("input[name='transition[idempotency_key]']", visible: false).map(&:value)).to eq(@keys)

      click_on "Reject"
      expect(page).to have_css("#notice", text: /Not applied: this invoice changed since you opened it/)
      # The conflict answer shows the current version, so the form now acts on it, with a fresh key.
      expect(all("input[name='transition[expected_version]']", visible: false).map(&:value)).to eq(%w[5 5])
      expect(page).to have_text("You are deciding on version 5.")
      expect(all("input[name='transition[idempotency_key]']", visible: false).map(&:value)).not_to include(*@keys)
      click_on "Reject"
      expect(page).to have_css("#notice", text: "Invoice rejected.")
    end
    expect(invoice.reload).to have_attributes(status: "rejected", version: 6)
  end

  it "keeps the user's own outcome notice when a refresh arrives after it" do
    using_session(:bob) do
      open_as(bob, invoice_path(invoice))
      fill_in "Reason for rejection (required)", with: "No purchase order"
    end
    approve_as_alice

    using_session(:bob) do
      click_on "Reject"
      expect(page).to have_css("#notice", text: /Not applied: this invoice changed since you opened it/)
    end
    invoice.update!(vendor_name: "Renamed Later") # another change: a refresh signal that lands after Bob's answer

    using_session(:bob) do
      expect(page).to have_css("h1", text: "Renamed Later") # the refresh was applied
      expect(page).to have_css("#notice", text: /Not applied: this invoice changed since you opened it/)
    end
  end

  it "refreshes the list, still filtered by the viewer's visibility" do
    requester = create(:user, company:)
    own = create(:invoice, company:, submitted_by: requester, vendor_name: "Own Draft")
    using_session(:requester) { open_as(requester, invoices_path) }

    approve_as_alice # someone else's invoice changed: signalled, but still not visible to the requester
    TransitionInvoice.call(actor: requester, invoice_uuid: own.uuid, action: "submit", expected_version: own.version, idempotency_key: SecureRandom.uuid)

    using_session(:requester) do
      expect(page).to have_css("tbody tr", count: 1, text: "Own Draft")
      expect(page).to have_css("tbody tr", text: "Pending approval")
      expect(page).to have_no_text("Live Vendor")
    end
  end
end
