require "rails_helper"

RSpec.describe "Factories" do
  it "are all valid" do
    FactoryBot.lint traits: true
  end

  it "use only reserved example.com email addresses" do
    emails = Array.new(3) { build(:user).email_address } + [ build(:user, :admin).email_address ]
    expect(emails).to all(end_with("@example.com"))
  end
end
