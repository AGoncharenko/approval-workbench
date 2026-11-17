require "rails_helper"

RSpec.describe "Admin user management" do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:, name: "Ada Admin") }
  let!(:approver) { create(:user, :approver, company:, name: "Alex Approver", email_address: "alex@example.com") }
  let!(:foreign) { create(:user, :approver, name: "Foreign Approver") }

  before { sign_in_as admin }

  def page = Nokogiri::HTML(response.body)
  def row_for(user) = page.css("tbody tr").find { it.text.include?(user.email_address) }
  def notice = page.at_css("#notice").text.squish

  it "lists every company user with name, email and role, and no other company's user" do
    get admin_users_path
    expect(response).to have_http_status(:ok)
    expect(page.css("tbody tr").map { it.css("td").first(2).map { |td| td.text.squish } })
      .to contain_exactly([ "Ada Admin", admin.email_address ], [ "Alex Approver", "alex@example.com" ])
    expect(response.body).not_to include("Foreign Approver")
  end

  it "gives each other user a labelled role select, and the admin's own row none" do
    get admin_users_path
    select = row_for(approver).at_css("select")
    expect(select.at_css("option[selected]")["value"]).to eq("approver")
    expect(page.at_css("label[for='#{select["id"]}']").text).to eq("Role for Alex Approver")
    expect(row_for(admin).at_css("select")).to be_nil
    expect(row_for(admin).text).to include("Admin")
  end

  it "changes a role with a confirmation naming the user and the old and new role, and audits it" do
    patch admin_user_path(approver), params: { user: { role: "requester" } }
    expect(response).to redirect_to(admin_users_path)
    expect(response).to have_http_status(:see_other)
    follow_redirect!
    expect(notice).to eq("Alex Approver changed from Approver to Requester. The new role applies from their next request.")
    expect(row_for(approver).at_css("option[selected]")["value"]).to eq("requester")
    expect(RoleChangeEvent.sole).to have_attributes(actor: admin, target_user: approver, from_role: "approver", to_role: "requester")
  end

  it "reports an unchanged role without writing an event" do
    patch admin_user_path(approver), params: { user: { role: "approver" } }
    follow_redirect!
    expect(notice).to eq("No change: Alex Approver is already Approver.")
    expect(RoleChangeEvent.count).to eq(0)
  end

  it "responds 404 for another company's user UUID and leaves them unchanged" do
    patch admin_user_path(foreign), params: { user: { role: "requester" } }
    expect(response).to have_http_status(:not_found)
    expect(page.at("h1").text).to eq("User not available")
    expect(foreign.reload.role).to eq("approver")
  end

  it "ignores forged company_id, email and name params" do
    other_company = create(:company)
    patch admin_user_path(approver), params: { user: { role: "admin", company_id: other_company.id, email_address: "forged@example.com", name: "Forged" } }
    expect(approver.reload).to have_attributes(role: "admin", company_id: company.id, email_address: "alex@example.com", name: "Alex Approver")
  end

  it "refuses an admin's own role change with 403" do
    patch admin_user_path(admin), params: { user: { role: "requester" } }
    expect(response).to have_http_status(:forbidden)
    expect(notice).to eq("Not allowed: you can't change your own role. Another admin can. Nothing was changed.")
    expect(admin.reload.role).to eq("admin")
    expect(RoleChangeEvent.count).to eq(0)
  end

  it "re-renders the index with 422 and an error on that row for a role outside the enum" do
    patch admin_user_path(approver), params: { user: { role: "owner" } }
    expect(response).to have_http_status(:unprocessable_content)
    select = row_for(approver).at_css("select")
    error = row_for(approver).at_css("##{select["aria-describedby"]}")
    expect(error.text).to eq("Not changed: choose Requester, Approver or Admin.")
    expect(select["aria-invalid"]).to eq("true")
    expect(approver.reload.role).to eq("approver")
    expect(RoleChangeEvent.count).to eq(0)
  end
end
