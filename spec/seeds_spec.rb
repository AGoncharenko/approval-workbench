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

  it "creates a stable set of DRAFT invoices in USD, EUR and JPY, authored by each company's requester" do
    load_seeds
    first = Invoice.order(:id).pluck(:id, :vendor_name, :total_minor_units, :currency, :due_date)
    load_seeds

    expect(Invoice.order(:id).pluck(:id, :vendor_name, :total_minor_units, :currency, :due_date)).to eq(first)
    expect(Invoice.joins(:company).group("companies.name").count).to eq("Acme Industries" => 8, "Globex Trading" => 7)
    expect(Invoice.distinct.pluck(:currency)).to contain_exactly("USD", "EUR", "JPY")
    expect(Invoice.distinct.pluck(:status, :version)).to eq([ [ "draft", 1 ] ])
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
end
