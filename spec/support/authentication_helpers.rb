module AuthenticationHelpers
  def sign_in_as(user, password: "test-password-123")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

RSpec.configure { |config| config.include AuthenticationHelpers, type: :request }
