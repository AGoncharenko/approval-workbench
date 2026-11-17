require "rails_helper"

RSpec.describe "Admin area access" do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:) }
  let(:colleague) { create(:user, :approver, company:) }

  def visit_every_admin_route
    get admin_users_path
    yield
    patch admin_user_path(colleague), params: { user: { role: "admin" } }
    yield
    get admin_audit_events_path
    yield
  end

  %i[requester approver].each do |role|
    it "refuses a #{role} on every admin route with 403 and changes nothing" do
      sign_in_as create(:user, role:, company:)
      visit_every_admin_route do
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include("Only admins can open the admin pages.")
      end
      expect(colleague.reload.role).to eq("approver")
      expect(RoleChangeEvent.count).to eq(0)
    end
  end

  it "re-reads the role per request: an admin demoted mid-session is refused on the next request" do
    sign_in_as admin
    get admin_users_path
    expect(response).to have_http_status(:ok)
    admin.update!(role: "requester")
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
  end

  it "redirects anonymous requests to sign-in" do
    get admin_audit_events_path
    expect(response).to redirect_to(new_session_path)
  end

  it "has no show or edit page: GET /admin/users/:uuid is 404" do
    sign_in_as admin
    get "/admin/users/#{colleague.uuid}"
    expect(response).to have_http_status(:not_found)
    get "/admin/users/#{colleague.uuid}/edit"
    expect(response).to have_http_status(:not_found)
  end
end
