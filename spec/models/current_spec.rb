require "rails_helper"

RSpec.describe Current do
  it "derives user and company from the session" do
    session = create(:session)
    Current.session = session

    expect(Current.user).to eq(session.user)
    expect(Current.company).to eq(session.user.company)
  end

  it "is empty without a session" do
    expect(Current.user).to be_nil
    expect(Current.company).to be_nil
  end
end
