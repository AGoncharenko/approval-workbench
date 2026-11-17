require "rails_helper"

RSpec.describe "db/seeds.rb" do
  def load_seeds = Rails.application.load_seed

  def roles_by_email
    User.joins(:company).order(:email_address).pluck(:email_address, "companies.name", :role)
  end

  it "is idempotent and creates the documented accounts" do
    load_seeds
    first = roles_by_email
    load_seeds

    expect(Company.count).to eq(2)
    expect(User.count).to eq(8)
    expect(roles_by_email).to eq(first)
    expect(first).to include(
      [ "requester@acme.example.com", "Acme Industries", "requester" ],
      [ "approver1@acme.example.com", "Acme Industries", "approver" ],
      [ "approver2@acme.example.com", "Acme Industries", "approver" ],
      [ "admin@acme.example.com", "Acme Industries", "admin" ],
      [ "requester@globex.example.com", "Globex Trading", "requester" ],
      [ "admin@globex.example.com", "Globex Trading", "admin" ]
    )
    expect(User.pluck(:email_address)).to all(end_with(".example.com"))
  end

  it "creates a stable set of invoices in USD, EUR and JPY, authored by each company's requester" do
    load_seeds
    first = Invoice.order(:id).pluck(:id, :vendor_name, :total_minor_units, :currency, :due_date, :status, :version)
    load_seeds

    expect(Invoice.order(:id).pluck(:id, :vendor_name, :total_minor_units, :currency, :due_date, :status, :version)).to eq(first)
    expect(Invoice.joins(:company).group("companies.name").count).to eq("Acme Industries" => 8, "Globex Trading" => 7)
    expect(Invoice.distinct.pluck(:currency)).to contain_exactly("USD", "EUR", "JPY")
    expect(Invoice.joins(:submitted_by).distinct.pluck("users.role")).to eq([ "requester" ])
    expect(Invoice.joins(:submitted_by).where("users.company_id <> invoices.company_id")).to be_empty
    expect(Invoice.minimum(:due_date)).to be > Date.current
  end

  it "lets every seeded user sign in with the default demo password" do
    load_seeds
    User.find_each do |user|
      expect(User.authenticate_by(email_address: user.email_address, password: "demo-password-2026")).to eq(user)
    end
  end

  it "uses DEMO_PASSWORD when set, rejecting the default" do
    original = ENV["DEMO_PASSWORD"]
    ENV["DEMO_PASSWORD"] = "operator-chosen-pass"
    load_seeds

    expect(User.authenticate_by(email_address: "admin@globex.example.com", password: "operator-chosen-pass")).to be_present
    expect(User.authenticate_by(email_address: "admin@globex.example.com", password: "demo-password-2026")).to be_nil
  ensure
    ENV["DEMO_PASSWORD"] = original
  end

  describe "seeded workflow history" do
    def history(invoice) = invoice.approval_history.map { [ it.action, it.actor.email_address, it.from_status, it.to_status ] }

    it "reaches every non-draft status through the real transitions, leaving drafts and pending work in each company" do
      load_seeds
      counts = Invoice.joins(:company).group("companies.name", :status).count
      expect(counts).to eq(
        [ "Acme Industries", "draft" ] => 4, [ "Acme Industries", "pending" ] => 2,
        [ "Acme Industries", "approved" ] => 1, [ "Acme Industries", "rejected" ] => 1,
        [ "Globex Trading", "draft" ] => 3, [ "Globex Trading", "pending" ] => 2,
        [ "Globex Trading", "approved" ] => 1, [ "Globex Trading", "rejected" ] => 1
      )
      expect(Invoice.draft.where(version: 1).count).to eq(7)
      expect(ApprovalEvent.where(invoice: Invoice.draft)).to be_empty
      Invoice.where.not(status: "DRAFT").find_each do |invoice|
        expect(invoice.version).to eq(1 + invoice.approval_events.count)
        expect(invoice.approval_history.first).to have_attributes(action: "submit", actor: invoice.submitted_by)
      end
    end

    it "gives an approved invoice a submit by its requester then an approve by a different approver, at version 3" do
      load_seeds
      approved = Invoice.find_by!(vendor_name: "Blue Harbor Logistics")
      expect(approved).to have_attributes(status: "approved", version: 3)
      expect(history(approved)).to eq([
        [ "submit", "requester@acme.example.com", "DRAFT", "PENDING" ],
        [ "approve", "approver1@acme.example.com", "PENDING", "APPROVED" ]
      ])
      expect(approved.approval_events.last.actor).not_to eq(approved.submitted_by)
      expect(Invoice.find_by!(vendor_name: "Hikari Components").approval_events.last).to have_attributes(
        action: "reject", reason: "Quantity does not match the purchase order.", actor: User.find_by!(email_address: "approver1@globex.example.com")
      )
    end

    it "adds no events and changes no versions when loaded again" do
      load_seeds
      events = ApprovalEvent.order(:id).pluck(:id, :invoice_id, :action)
      versions = Invoice.order(:id).pluck(:id, :status, :version)
      load_seeds
      expect(ApprovalEvent.order(:id).pluck(:id, :invoice_id, :action)).to eq(events)
      expect(Invoice.order(:id).pluck(:id, :status, :version)).to eq(versions)
      expect(IdempotencyKey.where("key LIKE 'seed:%'").count).to eq(events.size)
    end
  end
end
