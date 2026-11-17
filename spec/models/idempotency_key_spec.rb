require "rails_helper"

RSpec.describe IdempotencyKey do
  let(:user) { create(:user, :approver) }
  let(:row) { { company_id: user.company_id, user_id: user.id, key: "k-1", fingerprint: "a" * 64 } }

  it "is unique per company, user and key at the database level" do
    described_class.insert!(row)
    expect { described_class.insert!(row) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "lets another user use the same key" do
    other = create(:user, :approver, company: user.company)
    described_class.insert!(row)
    expect { described_class.insert!(row.merge(user_id: other.id)) }.not_to raise_error
  end
end
