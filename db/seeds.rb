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
