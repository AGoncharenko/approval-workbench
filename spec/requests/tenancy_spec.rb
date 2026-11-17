require "rails_helper"

RSpec.describe "Tenancy boundary" do
  let(:own) { create(:company, name: "Own Company") }
  let(:other) { create(:company, name: "Other Company") }
  let(:user) { create(:user, company: own) }

  before { sign_in_as(user) }

  it "ignores a forged company_id when rendering a protected page" do
    get root_path, params: { company_id: other.id, company: other.uuid }

    expect(response.body).to include("Own Company")
    expect(response.body).not_to include("Other Company")
  end

  it "ignores a forged company_id posted to a protected endpoint" do
    seen = nil
    allow_any_instance_of(SessionsController).to receive(:terminate_session).and_wrap_original do |original|
      seen = Current.company
      original.call
    end

    delete session_path, params: { company_id: other.id, company: { id: other.id } }

    expect(seen).to eq(own)
  end
end
