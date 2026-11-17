require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  it "rejects a client without a session cookie" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a cookie for a session that no longer exists" do
    session = user.sessions.create!
    cookies.signed[:session_id] = session.id
    session.destroy

    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects an unsigned session id" do
    cookies[:session_id] = user.sessions.create!.id

    expect { connect "/cable" }.to have_rejected_connection
  end

  it "accepts a signed session cookie and identifies the connection by its user" do
    cookies.signed[:session_id] = user.sessions.create!.id

    connect "/cable"
    expect(connection.current_user).to eq(user)
  end
end
