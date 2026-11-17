require "rails_helper"

RSpec.describe InvoicesHelper do
  let(:requester) { build(:user) }
  let(:approver) { build(:user, :approver) }

  it "labels every status from one locale source" do
    expect(Invoice.statuses.keys.map { helper.invoice_status_label(it) })
      .to eq([ "Draft", "Pending approval", "Approved (not paid)", "Rejected" ])
  end

  it "offers filter choices that follow the visibility rule" do
    expect(helper.invoice_status_options(requester).map(&:last)).to eq(%w[draft pending approved rejected])
    expect(helper.invoice_status_options(approver).map(&:last)).to eq(%w[pending approved rejected])
  end

  describe "#invoices_empty_message" do
    it "names the filtered status" do
      expect(helper.invoices_empty_message(status: "approved", user: approver)).to eq("No approved (not paid) invoices to show.")
    end

    it "explains each role's unfiltered empty list" do
      expect(helper.invoices_empty_message(status: nil, user: requester)).to eq("You have no invoices yet.")
      expect(helper.invoices_empty_message(status: nil, user: approver)).to include("Drafts stay private")
    end
  end
end

RSpec.describe ApplicationHelper do
  it "renders a machine-readable date without a zero-padded day" do
    expect(helper.date_tag(Date.new(2026, 12, 1))).to eq('<time datetime="2026-12-01">December 1, 2026</time>')
  end
end
