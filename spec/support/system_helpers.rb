module SystemHelpers
  def sign_in_through_ui(user, password: "test-password-123")
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: password
    click_on "Sign in"
    expect(page).to have_css("h1", text: "Invoices")
  end
end

RSpec.configure { |config| config.include SystemHelpers, type: :system }
