require "rails_helper"

RSpec.describe "Concurrency support", :concurrency do
  it "commits rows so other threads' connections can see them" do
    company = create(:company)
    seen = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Company.exists?(company.id) } }.value
    expect(seen).to be(true)
  end

  it "gives each thread its own database session, not one shared pinned connection" do
    main_pid = ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
    thread_pid = Thread.new { ActiveRecord::Base.connection_pool.with_connection { |c| c.select_value("SELECT pg_backend_pid()") } }.value
    expect(thread_pid).not_to eq(main_pid)
  end
end
