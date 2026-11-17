require "rails_helper"

RSpec.describe User do
  it "belongs to a company and exposes its uuid as the public param" do
    user = create(:user)

    expect(user.uuid).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    expect(user.to_param).to eq(user.uuid)
    expect(user.company.users).to include(user)
  end

  it "stores roles as readable strings" do
    expect(create(:user, :approver).role_before_type_cast).to eq("approver")
  end

  it "rejects an unknown role in the model" do
    expect(build(:user, role: "superuser")).not_to be_valid
  end

  it "rejects an unknown role in the database" do
    user = create(:user)
    expect { user.update_column(:role, "superuser") }.to raise_error(ActiveRecord::StatementInvalid, /users_role_allowed/)
  end

  it "rejects an over-long name in the database" do
    user = create(:user)
    expect { user.update_column(:name, "x" * 101) }.to raise_error(ActiveRecord::StatementInvalid, /users_name_length/)
  end

  it "requires a company in the database" do
    user = create(:user)
    expect { user.update_column(:company_id, nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "normalizes the email address" do
    expect(build(:user, email_address: " Someone@Example.COM ").email_address).to eq("someone@example.com")
  end

  it "cascades deletion to sessions in the database, not only in Rails" do
    session = create(:session)
    User.where(id: session.user_id).delete_all
    expect(Session.exists?(session.id)).to be(false)
  end
end
