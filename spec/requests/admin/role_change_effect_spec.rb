require "rails_helper"

RSpec.describe "A role change takes effect on the user's next request" do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:) }
  let(:approver) { create(:user, :approver, company:) }
  let!(:invoice) { create(:invoice, :pending, company:, version: 3) }

  def signed_in(user)
    open_session.tap { it.post session_path, params: { email_address: user.email_address, password: "test-password-123" } }
  end

  it "refuses the demoted approver's next decision in their existing session, without signing them out" do
    approver_session = signed_in(approver)
    admin_session = signed_in(admin)

    approver_session.get invoice_path(invoice)
    expect(approver_session.response.body).to include("Approve")

    admin_session.patch admin_user_path(approver), params: { user: { role: "requester" } }
    expect(admin_session.response).to have_http_status(:see_other)

    approver_session.post invoice_transitions_path(invoice), params: {
      transition: { action: "approve", expected_version: 3, idempotency_key: SecureRandom.uuid }
    }
    expect(approver_session.response).to have_http_status(:not_found)
    expect(approver_session.response.body).to include("Invoice not available")
    expect(invoice.reload).to have_attributes(status: "pending", version: 3)
    expect(ApprovalEvent.count).to eq(0)

    approver_session.get invoices_path # still signed in, now as a requester
    expect(approver_session.response).to have_http_status(:ok)
    expect(approver_session.response.body).to include("(requester)")
  end
end
