require "rails_helper"

RSpec.describe ChangeUserRole do
  let(:company) { create(:company) }
  let(:admin) { create(:user, :admin, company:) }
  let(:approver) { create(:user, :approver, company:) }

  def run(actor: admin, user: approver, role: "requester") = described_class.call(actor:, user_uuid: user.uuid, role:)

  def expect_nothing_written
    expect(RoleChangeEvent.count).to eq(0)
    expect(approver.reload.role).to eq("approver")
  end

  it "applies a change and writes exactly one event with the actor, target, old and new role" do
    result = run
    expect(result).to have_attributes(outcome: :applied, user: approver, from_role: "approver")
    expect(approver.reload.role).to eq("requester")
    expect(RoleChangeEvent.sole).to have_attributes(company:, actor: admin, target_user: approver, from_role: "approver", to_role: "requester")
  end

  it "can promote another user to admin" do
    expect(run(role: "admin").outcome).to eq(:applied)
    expect(approver.reload).to be_admin
  end

  it "is not_found for another company's user, and leaves them unchanged" do
    foreign = create(:user, :approver)
    expect(run(user: foreign).outcome).to eq(:not_found)
    expect(foreign.reload.role).to eq("approver")
    expect(RoleChangeEvent.count).to eq(0)
  end

  it "is not_found for an unknown or malformed UUID" do
    expect(described_class.call(actor: admin, user_uuid: SecureRandom.uuid, role: "requester").outcome).to eq(:not_found)
    expect(described_class.call(actor: admin, user_uuid: "not-a-uuid", role: "requester").outcome).to eq(:not_found)
  end

  it "forbids an admin changing their own role" do
    expect(run(user: admin).outcome).to eq(:forbidden)
    expect(admin.reload.role).to eq("admin")
    expect(RoleChangeEvent.count).to eq(0)
  end

  it "refuses a role outside the enum as invalid" do
    expect(run(role: "owner")).to have_attributes(outcome: :invalid, error: :role)
    expect(run(role: nil)).to have_attributes(outcome: :invalid, error: :role)
    expect_nothing_written
  end

  it "reports an unchanged role without writing an event" do
    expect(run(role: "approver").outcome).to eq(:unchanged)
    expect_nothing_written
  end

  it "refuses to demote the last admin, even for an actor who was an admin when the request began" do
    stale_admin = User.find(admin.id)
    other_admin = create(:user, :admin, company:)
    admin.update!(role: "requester") # demoted elsewhere since stale_admin was loaded
    expect(run(actor: stale_admin, user: other_admin)).to have_attributes(outcome: :invalid, error: :last_admin)
    expect(other_admin.reload.role).to eq("admin")
    expect(RoleChangeEvent.count).to eq(0)
  end

  it "forbids an actor demoted since the request began when other admins remain" do
    stale_admin = User.find(admin.id)
    create(:user, :admin, company:)
    admin.update!(role: "requester")
    expect(run(actor: stale_admin).outcome).to eq(:forbidden)
    expect_nothing_written
  end

  it "rolls the role back when the event insert fails" do
    allow(RoleChangeEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "forced failure")
    expect { run }.to raise_error(ActiveRecord::StatementInvalid, "forced failure")
    expect_nothing_written
  end
end
