require "rails_helper"

RSpec.describe "Concurrency support", :concurrency do
  it "commits rows so other threads' connections can see them" do
    company = create(:company)
    seen = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Company.exists?(company.id) } }.value
    expect(seen).to be(true)
  end
end
