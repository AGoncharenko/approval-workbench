# Synthetic demo data: fixed literals, safe to run repeatedly in every environment.
# Uses only runtime gems (no FactoryBot). Existing records are left untouched on re-run.
password = ENV.fetch("DEMO_PASSWORD", "demo-password-2026")

{
  [ "Acme Industries", "acme" ] => [
    [ "Rita Requester", "requester", "requester" ],
    [ "Alex Approver", "approver1", "approver" ],
    [ "Blair Approver", "approver2", "approver" ],
    [ "Ada Admin", "admin", "admin" ]
  ],
  [ "Globex Trading", "globex" ] => [
    [ "Remy Requester", "requester", "requester" ],
    [ "Gale Approver", "approver1", "approver" ],
    [ "Morgan Approver", "approver2", "approver" ],
    [ "Grace Admin", "admin", "admin" ]
  ]
}.each do |(company_name, domain), users|
  company = Company.find_or_create_by!(name: company_name)

  users.each do |name, mailbox, role|
    User.find_or_create_by!(email_address: "#{mailbox}@#{domain}.example.com") do |user|
      user.assign_attributes(company:, name:, role:, password:)
    end
  end
end

# DRAFT invoices only: later statuses are reached through real commands so every status has audit history.
# Amounts are integer minor units; due dates are offsets from the load date so the demo never looks stale.
{
  "requester@acme.example.com" => [
    [ "Northwind Office Supply", 48_250, "USD", 7 ],
    [ "Blue Harbor Logistics", 1_275_000, "USD", 14 ],
    [ "Cedar Analytics", 389_900, "EUR", 21 ],
    [ "Kumo Translation KK", 165_000, "JPY", 10 ],
    [ "Lumen Facilities", 92_000, "EUR", 30 ],
    [ "Granite Cloud Hosting", 2_499_999, "USD", 5 ],
    [ "Sakura Print Works", 4_820_000, "JPY", 45 ],
    [ "Fjord Travel Services", 61_340, "EUR", 3 ]
  ],
  "requester@globex.example.com" => [
    [ "Orion Freight", 3_315_075, "USD", 12 ],
    [ "Atlas Legal LLP", 750_000, "EUR", 28 ],
    [ "Hikari Components", 12_600_000, "JPY", 9 ],
    [ "Meridian Catering", 18_420, "USD", 2 ],
    [ "Vega Security", 455_500, "EUR", 18 ],
    [ "Tanuki Software", 980_000, "JPY", 35 ],
    [ "Pinecrest Maintenance", 129_995, "USD", 60 ]
  ]
}.each do |email, invoices|
  author = User.find_by!(email_address: email)

  invoices.each do |vendor_name, total_minor_units, currency, due_in_days|
    Invoice.find_or_create_by!(company: author.company, vendor_name:) do |invoice|
      invoice.assign_attributes(submitted_by: author, total_minor_units:, currency:, due_date: Date.current + due_in_days)
    end
  end
end
