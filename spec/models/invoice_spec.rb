require "rails_helper"

RSpec.describe Invoice do
  let!(:invoice) { create(:invoice) }

  # update_all skips model validations so these prove the database itself refuses the write;
  # the savepoint keeps the example's transaction usable after each refusal.
  def db_write(attrs) = Invoice.transaction(requires_new: true) { Invoice.where(id: invoice.id).update_all(attrs) }

  it "rejects an unknown status in the database" do
    expect { db_write(status: "PAID") }.to raise_error(ActiveRecord::StatementInvalid, /invoices_status_allowed/)
  end

  it "rejects a negative or over-maximum total in the database" do
    expect { db_write(total_minor_units: -1) }.to raise_error(ActiveRecord::StatementInvalid, /invoices_total_range/)
    expect { db_write(total_minor_units: 100_000_000_000_000) }.to raise_error(ActiveRecord::StatementInvalid, /invoices_total_range/)
    expect { db_write(total_minor_units: 99_999_999_999_999) }.not_to raise_error
  end

  it "rejects a malformed or missing currency in the database" do
    %w[usd US1 EU].each do |bad|
      expect { db_write(currency: bad) }.to raise_error(ActiveRecord::StatementInvalid, /invoices_currency_format/)
    end
    expect { db_write(currency: nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "starts at version 1 as a draft" do
    expect(invoice.reload).to have_attributes(version: 1, status: "draft")
    expect(Invoice.connection.select_value("SELECT status FROM invoices WHERE id = #{invoice.id}")).to eq("DRAFT")
  end

  it "is assigned a database-generated UUID used as its URL parameter" do
    fresh = Invoice.create!(attributes_for(:invoice).merge(company: invoice.company, submitted_by: invoice.submitted_by))
    expect(fresh.reload.uuid).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    expect(fresh.to_param).to eq(fresh.uuid)
  end

  it "exposes its total as Money, never a Float" do
    expect(invoice.total).to eq(Money.new(123_456, "USD"))
    expect(invoice.total.to_s).to eq("USD 1,234.56")
  end

  it "refuses an author from another company" do
    expect(build(:invoice, company: create(:company))).to be_valid
    expect(build(:invoice, company: create(:company), submitted_by: invoice.submitted_by)).not_to be_valid
  end

  it "treats APPROVED and REJECTED as terminal" do
    expect(Invoice::STATUSES.select { build(:invoice, status: it).terminal? }).to eq(%w[APPROVED REJECTED])
  end
end
