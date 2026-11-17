require "rails_helper"

RSpec.describe "Drafts" do
  let(:company) { create(:company) }
  let(:requester) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }
  let(:valid) { { vendor_name: "Northwind", amount: "1,234.56", currency: "USD", due_date: "2026-12-01" } }

  def page = Nokogiri::HTML(response.body)
  def notice = page.at_css("#notice").text.squish
  def field_error(attribute) = page.at_css("#invoice_#{attribute}_error")&.text

  describe "new / create" do
    it "creates a DRAFT at version 1 in the requester's company, with them as author" do
      sign_in_as requester
      get new_invoice_path
      expect(response).to have_http_status(:ok)
      expect(page.css("select[name='invoice[currency]'] option").map(&:text).compact_blank).to eq(%w[USD EUR GBP JPY BHD])

      expect { post invoices_path, params: { invoice: valid } }.to change(Invoice, :count).by(1)
      invoice = Invoice.last
      expect(response).to redirect_to(invoice_path(invoice))
      expect(response).to have_http_status(:see_other)
      expect(invoice).to have_attributes(company:, submitted_by: requester, status: "draft", version: 1,
        vendor_name: "Northwind", total_minor_units: 123_456, currency: "USD", due_date: Date.new(2026, 12, 1))
      expect(ApprovalEvent.count).to eq(0)
    end

    it "ignores a forged company_id and submitted_by_id" do
      other = create(:company)
      sign_in_as requester
      post invoices_path, params: { invoice: valid.merge(company_id: other.id, submitted_by_id: create(:user, company: other).id), company_id: other.id }
      expect(Invoice.sole).to have_attributes(company:, submitted_by: requester)
    end

    it "refuses approvers and admins with 403 and creates nothing" do
      [ approver, create(:user, :admin, company:) ].each do |user|
        sign_in_as user
        get new_invoice_path
        expect(response).to have_http_status(:forbidden)
        post invoices_path, params: { invoice: valid }
        expect(response).to have_http_status(:forbidden)
      end
      expect(Invoice.count).to eq(0)
    end

    {
      [ "10.005", "USD" ] => "Amount must be a number of 0 or more with at most 2 decimal places for USD, up to 999,999,999,999.99",
      [ "1.5", "JPY" ] => "Amount must be a number of 0 or more with at most 0 decimal places for JPY, up to 99,999,999,999,999",
      [ "1,000,000,000,000.00", "USD" ] => "Amount must be a number of 0 or more with at most 2 decimal places for USD, up to 999,999,999,999.99",
      [ "-5", "USD" ] => "Amount must be a number of 0 or more with at most 2 decimal places for USD, up to 999,999,999,999.99",
      [ "abc", "EUR" ] => "Amount must be a number of 0 or more with at most 2 decimal places for EUR, up to 999,999,999,999.99",
      [ "", "USD" ] => "Amount can't be blank"
    }.each do |(amount, currency), message|
      it "rejects #{amount.inspect} #{currency} with an amount field error and saves nothing" do
        sign_in_as requester
        post invoices_path, params: { invoice: valid.merge(amount:, currency:) }
        expect(response).to have_http_status(:unprocessable_content)
        expect(field_error(:amount)).to eq(message)
        expect(page.at_css("input[name='invoice[amount]']")["value"]).to eq(amount)
        expect(Invoice.count).to eq(0)
      end
    end

    it "requires vendor, a supported currency and a due date" do
      sign_in_as requester
      post invoices_path, params: { invoice: { vendor_name: "x" * 201, amount: "1", currency: "XTS", due_date: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect([ field_error(:vendor_name), field_error(:currency), field_error(:due_date) ]).to eq(
        [ "Vendor name is too long (maximum is 200 characters)", "Currency is not included in the list", "Due date can't be blank" ]
      )
      expect(Invoice.count).to eq(0)
    end
  end

  describe "edit / update" do
    let(:draft) { create(:invoice, company:, submitted_by: requester, vendor_name: "Old Vendor", total_minor_units: 100, currency: "USD") }

    def save(expected_version: 1, invoice: draft, **changes)
      patch invoice_path(invoice), params: { expected_version:, invoice: valid.merge(changes) }
    end

    it "prefills the form with the exact amount and saves at the expected version, bumping it" do
      sign_in_as requester
      get edit_invoice_path(draft)
      expect(page.at_css("input[name='invoice[amount]']")["value"]).to eq("1.00")
      expect(page.at_css("input[name=expected_version]")["value"]).to eq("1")

      save(amount: "0.001", currency: "BHD")
      expect(response).to redirect_to(invoice_path(draft))
      expect(draft.reload).to have_attributes(vendor_name: "Northwind", total_minor_units: 1, currency: "BHD", version: 2, status: "draft")
      expect(ApprovalEvent.count).to eq(0)
    end

    it "reports a stale edit as 409, shows the current values and overwrites nothing" do
      draft.update_columns(vendor_name: "Changed In Other Tab", version: 2)
      sign_in_as requester
      save(vendor_name: "My Stale Edit")
      expect(response).to have_http_status(:conflict)
      expect(notice).to start_with("Not saved: this draft changed since you opened it")
      expect(notice).to include("version 2")
      expect(page.at_css("input[name='invoice[vendor_name]']")["value"]).to eq("Changed In Other Tab")
      expect(page.at_css("input[name=expected_version]")["value"]).to eq("2")
      expect(draft.reload).to have_attributes(vendor_name: "Changed In Other Tab", version: 2)
    end

    it "keeps the version the form was opened at when re-rendering a field error" do
      draft.update_columns(version: 2)
      sign_in_as requester
      save(amount: "1.234")
      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css("input[name=expected_version]")["value"]).to eq("1")
    end

    it "refuses a missing expected_version with 422" do
      sign_in_as requester
      patch invoice_path(draft), params: { invoice: valid }
      expect(response).to have_http_status(:unprocessable_content)
      expect(draft.reload.version).to eq(1)
    end

    it "refuses to edit or discard a submitted invoice with 403, leaving it unchanged" do
      submitted = create(:invoice, :pending, company:, submitted_by: requester, vendor_name: "Submitted", version: 2)
      sign_in_as requester
      get edit_invoice_path(submitted)
      expect(response).to have_http_status(:forbidden)
      save(invoice: submitted, expected_version: 2, vendor_name: "Hacked")
      expect(response).to have_http_status(:forbidden)
      delete invoice_path(submitted)
      expect(response).to have_http_status(:forbidden)
      expect(submitted.reload).to have_attributes(vendor_name: "Submitted", status: "pending", version: 2)
    end

    it "answers 404 for another user's draft and for another company's, and 403 for an approver on a visible invoice" do
      sign_in_as create(:user, company:)
      get edit_invoice_path(draft)
      expect(response).to have_http_status(:not_found)
      save(vendor_name: "Hacked")
      expect(response).to have_http_status(:not_found)

      sign_in_as approver
      save(vendor_name: "Hacked")
      expect(response).to have_http_status(:not_found) # drafts are author-only
      pending = create(:invoice, :pending, company:, submitted_by: requester)
      save(invoice: pending, vendor_name: "Hacked")
      expect(response).to have_http_status(:forbidden)

      sign_in_as create(:user, company: create(:company))
      save(vendor_name: "Hacked")
      expect(response).to have_http_status(:not_found)
      expect(draft.reload).to have_attributes(vendor_name: "Old Vendor", version: 1)
    end
  end

  describe "destroy" do
    let!(:draft) { create(:invoice, company:, submitted_by: requester, vendor_name: "Doomed Draft") }

    it "discards the author's own draft" do
      sign_in_as requester
      delete invoice_path(draft)
      expect(response).to redirect_to(invoices_path)
      follow_redirect!
      expect(notice).to eq("Draft for Doomed Draft discarded.")
      expect(Invoice.exists?(draft.id)).to be(false)
    end

    it "answers 404 when discarding another user's draft" do
      sign_in_as create(:user, company:)
      delete invoice_path(draft)
      expect(response).to have_http_status(:not_found)
      expect(Invoice.exists?(draft.id)).to be(true)
    end
  end

  describe "submit button" do
    let(:draft) { create(:invoice, company:, submitted_by: requester) }

    def submit_form = page.at_xpath("//form[.//input[@name='transition[action]' and @value='submit']]")

    it "is on the author's draft page with the current version and a fresh key, and submits through the transition" do
      sign_in_as requester
      get invoice_path(draft)
      form = submit_form
      expect(form["action"]).to eq(invoice_transitions_path(draft))
      expect(form.at_css("input[name='transition[expected_version]']")["value"]).to eq("1")
      key = form.at_css("input[name='transition[idempotency_key]']")["value"]
      expect(key).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      get invoice_path(draft)
      expect(submit_form.at_css("input[name='transition[idempotency_key]']")["value"]).not_to eq(key)

      params = { transition: { action: "submit", expected_version: 1, idempotency_key: key } }
      post invoice_transitions_path(draft), params: params
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(notice).to eq("Invoice submitted for approval. Approvers in your company can now see it.")
      expect(draft.reload).to have_attributes(status: "pending", version: 2)
      expect(submit_form).to be_nil
      expect(page.at_xpath("//a[text()='Edit draft']")).to be_nil

      post invoice_transitions_path(draft), params: params
      follow_redirect!
      expect(notice).to start_with("Already recorded: this invoice was submitted at")
      expect(ApprovalEvent.where(invoice: draft, action: "submit").count).to eq(1)
    end

    it "reports a stale submit as a 409 conflict" do
      sign_in_as requester
      post invoice_transitions_path(draft), params: { transition: { action: "submit", expected_version: 0, idempotency_key: "k" } }
      expect(response).to have_http_status(:conflict)
      expect(notice).to eq("Not applied: this invoice changed since you opened it. It is now Draft (version 1).")
    end

    it "answers 404 when another requester submits the draft" do
      sign_in_as create(:user, company:)
      post invoice_transitions_path(draft), params: { transition: { action: "submit", expected_version: 1, idempotency_key: "k" } }
      expect(response).to have_http_status(:not_found)
      expect(draft.reload.status).to eq("draft")
    end

    it "is not shown to approvers, and the index offers New invoice only to requesters" do
      sign_in_as approver
      get invoice_path(create(:invoice, :pending, company:, submitted_by: requester))
      expect(submit_form).to be_nil
      get invoices_path
      expect(page.at_xpath("//a[text()='New invoice']")).to be_nil
      sign_in_as requester
      get invoices_path
      expect(page.at_xpath("//a[text()='New invoice']")["href"]).to eq(new_invoice_path)
    end
  end
end
