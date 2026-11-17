require "rails_helper"

RSpec.describe "Request logging" do
  let(:company) { create(:company) }
  let(:author) { create(:user, company:) }
  let(:approver) { create(:user, :approver, company:) }
  let!(:invoice) { create(:invoice, :pending, company:, submitted_by: author) }
  let(:log) { StringIO.new }

  around do |example|
    # Production logs at info (RAILS_LOG_LEVEL); debug-level SQL lines carry literal values and are not shipped there.
    capture = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log, level: :info))
    Rails.logger.broadcast_to(capture)
    example.run
  ensure
    Rails.logger.stop_broadcasting_to(capture)
  end

  it "filters the password from the sign-in parameters" do
    sign_in_as approver

    expect(log.string).to include('"password" => "[FILTERED]"')
    expect(log.string).not_to include("test-password-123")
  end

  it "tags an approval with request id, user and company, and filters the idempotency key" do
    sign_in_as approver
    log.truncate(0)
    log.rewind

    post invoice_transitions_path(invoice),
      params: { transition: { action: "approve", expected_version: invoice.version, idempotency_key: "secret-key-123" } }

    request_id = response.headers["X-Request-Id"]
    lines = log.string.lines
    expect(lines).to all(include("[#{request_id}]"))
    expect(lines.grep(/\[user=#{approver.uuid}\] \[company=#{company.uuid}\]/)).not_to be_empty
    expect(log.string).to include('"idempotency_key" => "[FILTERED]"')
    expect(log.string).not_to include("secret-key-123")
    expect(log.string).to include("Completed 303 See Other")
  end
end
