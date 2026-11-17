require "rails_helper"

RSpec.describe "Sessions" do
  let(:user) { create(:user, name: "Sam Signin") }

  it "signs in with valid credentials, creating a server-side session" do
    expect { sign_in_as(user) }.to change(user.sessions, :count).by(1)
    expect(response).to redirect_to(root_url)

    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    expect(set_cookie).to match(/session_id=/).and match(/httponly/i)
    expect(set_cookie).not_to include("session_id=#{user.sessions.last.id};")

    follow_redirect!
    expect(response.body).to include("Sam Signin")
  end

  it "fails with the same generic message for an unknown email or a wrong password" do
    messages = [
      { email_address: "nobody@example.com", password: "test-password-123" },
      { email_address: user.email_address, password: "wrong-password" }
    ].map do |params|
      expect { post session_path, params: params }.not_to change(Session, :count)
      expect(response).to redirect_to(new_session_path)
      flash[:alert]
    end

    expect(messages.uniq).to eq([ "Try another email address or password." ])
  end

  it "redirects anonymous requests to sign-in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "leaves the health check public" do
    get rails_health_check_path
    expect(response).to have_http_status(:ok)
  end

  it "destroys the session row on sign-out and redirects later requests" do
    sign_in_as(user)

    expect { delete session_path }.to change(Session, :count).by(-1)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "disconnects the user's realtime sockets on sign-out" do
    sign_in_as(user)

    expect { delete session_path }.to have_broadcasted_to("action_cable/#{user.to_gid_param}").with(type: "disconnect", reconnect: true)
  end

  it "treats a cookie replayed after sign-out as unauthenticated" do
    sign_in_as(user)
    stolen = cookies[:session_id]
    delete session_path

    cookies[:session_id] = stolen
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "removes sessions of a deleted user and redirects their next request" do
    sign_in_as(user)
    get root_path
    expect(response).to have_http_status(:ok)

    user.destroy!
    expect(Session.where(user_id: user.id)).to be_empty

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "re-reads the role from the database on every request" do
    sign_in_as(user)
    user.update!(role: "admin")

    get root_path
    expect(response.body).to include("(admin)")
  end

  describe "rate limit" do
    let(:memory) { ActiveSupport::Cache::MemoryStore.new }

    before do
      # Test env uses :null_store; route the limiter's counter through a real memory store.
      allow(SessionsController.cache_store).to receive(:increment) { |*args, **opts| memory.increment(*args, **opts) }
    end

    it "refuses the 11th attempt within 3 minutes" do
      10.times { post session_path, params: { email_address: user.email_address, password: "wrong" } }
      expect(flash[:alert]).to eq("Try another email address or password.")

      expect { sign_in_as(user) }.not_to change(Session, :count)
      expect(flash[:alert]).to eq("Try again later.")
    end
  end

  describe "sign-in page" do
    it "is labelled as a demo and lists demo accounts outside production" do
      user
      get new_session_path

      expect(response.body).to include("(demo)")
      expect(response.body).to include(user.email_address)
    end

    it "hides the account list in production" do
      user
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      get new_session_path

      expect(response.body).to include("(demo)")
      expect(response.body).not_to include(user.email_address)
    end
  end
end
