require "rails_helper"

RSpec.describe "Health check" do
  it "returns 200 with no body and no sign-in when the database answers" do
    get health_check_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end

  it "returns 503 when the database is unreachable" do
    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection)
      .and_raise(ActiveRecord::ConnectionNotEstablished, "connection refused")

    get health_check_path

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to be_empty
  end

  # Test runs without force_ssl, so wrap the app in the same SSL middleware and options production installs.
  context "behind production's force_ssl" do
    let(:production_like) do
      Rack::MockRequest.new(ActionDispatch::SSL.new(Rails.application, **Rails.application.config.ssl_options))
    end

    it "answers /up over plain HTTP instead of redirecting" do
      expect(production_like.get("http://www.example.com/up").status).to eq(200)
    end

    it "still redirects other plain HTTP requests to HTTPS" do
      response = production_like.get("http://www.example.com/session/new")

      expect(response.status).to eq(301)
      expect(response.location).to eq("https://www.example.com/session/new")
    end
  end
end
