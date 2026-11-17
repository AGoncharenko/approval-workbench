require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_have_broadcasted_to, :have_broadcasted_to

RSpec.describe Invoice, "change signals" do
  let(:company) { create(:company) }
  let(:approver) { create(:user, :approver, company:) }
  let!(:invoice) { create(:invoice, :pending, company:, vendor_name: "Signal Vendor", total_minor_units: 123_456, version: 3) }

  def stream(company) = "#{company.to_gid_param}:invoices" # what turbo_stream_from(company, :invoices) subscribes to

  def approve(invoice, actor: approver)
    TransitionInvoice.call(actor:, invoice_uuid: invoice.uuid, action: "approve", expected_version: invoice.version, idempotency_key: SecureRandom.uuid)
  end

  it "sends a bare refresh to the company stream when a decision commits" do
    expect { approve(invoice) }.to have_broadcasted_to(stream(company)).exactly(:once).with { |payload|
      expect(payload).to match(%r{\A<turbo-stream (request-id="[^"]*" )?action="refresh"></turbo-stream>\z})
      expect(payload).not_to include(invoice.uuid, invoice.vendor_name, "123456", "1234.56", "PENDING", "APPROVED", "approve")
    }
  end

  it "signals draft edits and discards too" do
    draft = create(:invoice, company:)

    expect { draft.update!(vendor_name: "Renamed Vendor") }.to have_broadcasted_to(stream(company))
    expect { draft.destroy! }.to have_broadcasted_to(stream(company))
  end

  it "sends nothing when the transaction rolls back" do
    expect {
      Invoice.transaction do
        invoice.update!(status: "APPROVED", version: 4)
        raise ActiveRecord::Rollback
      end
    }.not_to have_broadcasted_to(stream(company))
  end

  it "sends nothing for a refused (stale) decision" do
    expect {
      TransitionInvoice.call(actor: approver, invoice_uuid: invoice.uuid, action: "approve", expected_version: 2, idempotency_key: SecureRandom.uuid)
    }.not_to have_broadcasted_to(stream(company))
  end

  it "never signals another company's stream" do
    other = create(:company)
    other_invoice = create(:invoice, :pending, company: other)

    expect { approve(other_invoice, actor: create(:user, :approver, company: other)) }
      .to have_broadcasted_to(stream(other))
      .and not_have_broadcasted_to(stream(company))
  end
end
