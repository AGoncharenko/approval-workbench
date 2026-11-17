require "rails_helper"

RSpec.describe "Sign in", type: :system do
  it "signs in and out through the browser" do
    create(:user, name: "Browser Tester", email_address: "browser@example.com")

    visit root_path
    fill_in "Email address", with: "browser@example.com"
    fill_in "Password", with: "test-password-123"
    click_on "Sign in"
    expect(page).to have_text("Signed in as Browser Tester")

    click_on "Sign out"
    expect(page).to have_button("Sign in")
  end
end
