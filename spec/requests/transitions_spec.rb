require "rails_helper"

RSpec.describe "Invoice transitions" do
  let(:company) { create(:company) }
  let(:author) { create(:user, company:, name: "Rita Requester") }
  let(:approver) { create(:user, :approver, company:, name: "Alice Approver") }
  let(:invoice) { create(:invoice, :pending, company:, submitted_by: author, version: 7) }

  def decide(action: "approve", expected_version: 7, key: SecureRandom.uuid, reason: nil, uuid: invoice.uuid, **extra)
    post invoice_transitions_path(uuid), params: {
      transition: { action:, expected_version:, idempotency_key: key, reason: }.compact, **extra
    }
  end

  def notice = Nokogiri::HTML(response.body).at_css("#notice").text.squish

  context "as an approver" do
    before { sign_in_as approver }

    it "applies an approval with 303 and says so" do
      decide
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(invoice_path(invoice))
      follow_redirect!
      expect(notice).to eq("Invoice approved. This records the decision only; it does not pay the invoice.")
      expect(invoice.reload).to have_attributes(status: "approved", version: 8)
    end

    it "lists the decision in the history with actor, role, statuses, reason and time" do
      decide(action: "reject", reason: "Duplicate of INV-1")
      follow_redirect!
      item = Nokogiri::HTML(response.body).at_css("section[aria-labelledby=history-heading] ol li")
      expect(item.text.squish).to include("Rejected by Alice Approver (approver)", "Pending approval → to Rejected", "Reason: Duplicate of INV-1")
      expect(item.at_css("time")["datetime"]).to eq(ApprovalEvent.sole.created_at.iso8601)
      expect(notice).to eq("Invoice rejected.")
    end

    it "replays a retry with the same key as already recorded, with the original time" do
      decide(key: "k-1")
      original = ApprovalEvent.sole.created_at
      decide(key: "k-1")
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(notice).to eq("Already recorded: this decision was saved at #{I18n.l(original, format: :long)}. Nothing was applied twice.")
      expect(ApprovalEvent.count).to eq(1)
    end

    it "refuses a reused key with a different payload with 422" do
      decide(key: "k-1")
      decide(key: "k-1", action: "reject", reason: "Changed my mind")
      expect(response).to have_http_status(:unprocessable_content)
      expect(notice).to start_with("Not applied: this form was already used for a different decision.")
      expect(invoice.reload.status).to eq("approved")
    end

    it "refuses a missing key, or no transition params at all, with 422" do
      decide(key: nil)
      expect(response).to have_http_status(:unprocessable_content)
      post invoice_transitions_path(invoice.uuid)
      expect(response).to have_http_status(:unprocessable_content)
      expect(invoice.reload.version).to eq(7)
    end

    it "refuses a blank rejection reason with 422 and a field error" do
      decide(action: "reject", reason: " ")
      expect(response).to have_http_status(:unprocessable_content)
      field = Nokogiri::HTML(response.body).at_css("textarea[name='transition[reason]']")
      expect(field["aria-invalid"]).to eq("true")
      expect(response.body).to include("Enter a reason for the rejection.")
      expect(invoice.reload.status).to eq("pending")
    end

    it "reports a stale decision as a 409 conflict naming the current status, version and latest actor" do
      TransitionInvoice.call(actor: create(:user, :approver, company:, name: "Bob Approver"), invoice_uuid: invoice.uuid,
        action: "approve", expected_version: 7, idempotency_key: "bob")
      decide(action: "reject", reason: "No PO")
      expect(response).to have_http_status(:conflict)
      event = ApprovalEvent.sole
      expect(notice).to eq("Not applied: this invoice changed since you opened it. It is now Approved (not paid) (version 8), " \
        "last changed by Bob Approver at #{I18n.l(event.created_at, format: :long)}.")
      expect(response.body).not_to include("Reason for rejection") # controls reflect the current state
      expect(ApprovalEvent.count).to eq(1)
    end

    it "answers 404 for a draft, another company's invoice and an unknown UUID" do
      draft = create(:invoice, company:, submitted_by: author)
      foreign = create(:invoice, :pending, version: 7)
      [ draft.uuid, foreign.uuid, SecureRandom.uuid ].each do |uuid|
        decide(uuid:, expected_version: 1)
        expect(response).to have_http_status(:not_found)
      end
      expect(foreign.reload.status).to eq("pending")
    end

    it "ignores a forged company_id param" do
      foreign = create(:invoice, :pending, version: 7)
      decide(uuid: foreign.uuid, company_id: foreign.company_id, invoice: { company_id: foreign.company_id })
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.status).to eq("pending")
    end

    it "renders the decision forms with the expected version and a fresh key per render" do
      get invoice_path(invoice)
      forms = Nokogiri::HTML(response.body).css("form[action='#{invoice_transitions_path(invoice)}']")
      expect(forms.map { it.at_css("input[name='transition[action]']")["value"] }).to eq(%w[approve reject])
      expect(forms.map { it.at_css("input[name='transition[expected_version]']")["value"] }).to eq(%w[7 7])
      keys = forms.map { it.at_css("input[name='transition[idempotency_key]']")["value"] }
      expect(keys.uniq.size).to eq(2)
      expect(forms.last.at_css("textarea[name='transition[reason]'][required][maxlength='1000']")).to be_present
      expect(forms.css("button[data-turbo-submits-with]").map(&:text)).to eq(%w[Approve Reject])

      get invoice_path(invoice)
      expect(response.body).not_to include(*keys)
    end

    it "hides the controls on the approver's own invoice and on a decided one" do
      [ create(:invoice, :pending, company:, submitted_by: approver), create(:invoice, :approved, company:, submitted_by: author) ].each do |other|
        get invoice_path(other)
        expect(response.body).not_to include("transition[idempotency_key]")
      end
    end
  end

  context "as a requester" do
    before { sign_in_as author }

    it "is forbidden (403) on their own invoice and sees no decision controls" do
      get invoice_path(invoice)
      expect(response.body).not_to include("transition[idempotency_key]")

      decide
      expect(response).to have_http_status(:forbidden)
      expect(notice).to eq("Not allowed: you can't make this decision on this invoice. Nothing was changed.")
      expect(invoice.reload.version).to eq(7)
    end

    it "gets 404, not 403 or 409, for another requester's invoice, even when stale" do
      others = create(:invoice, :pending, company:, version: 7)
      decide(uuid: others.uuid, expected_version: 1)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "as an admin" do
    before { sign_in_as create(:user, :admin, company:) }

    it "is forbidden (403) and sees no decision controls" do
      get invoice_path(invoice)
      expect(response.body).not_to include("transition[idempotency_key]")
      decide
      expect(response).to have_http_status(:forbidden)
      expect(invoice.reload.status).to eq("pending")
    end
  end

  it "redirects a signed-out request to sign in without applying" do
    decide
    expect(response).to redirect_to(new_session_path)
    expect(invoice.reload.status).to eq("pending")
  end
end
