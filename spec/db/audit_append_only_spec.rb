require "rails_helper"

# The forbid_audit_mutation() trigger refuses UPDATE and DELETE below the application, whatever the code path.
RSpec.describe "Append-only audit tables" do
  let(:company) { create(:company) }
  let(:approver) { create(:user, :approver, company:) }
  let(:admin) { create(:user, :admin, company:) }
  let(:invoice) { create(:invoice, :pending, company:) }

  let!(:approval_event) do
    ApprovalEvent.create!(company:, invoice:, actor: approver, actor_role: "approver", action: "reject",
      from_status: "PENDING", to_status: "REJECTED", reason: "Original reason")
  end
  let!(:role_change_event) do
    RoleChangeEvent.create!(company:, actor: admin, target_user: approver, from_role: "approver", to_role: "requester")
  end

  def expect_refused(&)
    expect { ApplicationRecord.transaction(requires_new: true, &) }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end

  {
    ApprovalEvent => { reason: "Rewritten" },
    RoleChangeEvent => { to_role: "admin" }
  }.each do |model, change|
    describe model.table_name do
      let(:event) { model.find(model == ApprovalEvent ? approval_event.id : role_change_event.id) }
      let!(:original) { event.attributes }
      let(:connection) { ApplicationRecord.connection }

      it "refuses update_all and delete_all" do
        expect_refused { model.where(id: event.id).update_all(change) }
        expect_refused { model.where(id: event.id).delete_all }
        expect(model.find(event.id).attributes).to eq(original)
      end

      it "refuses raw SQL UPDATE and DELETE" do
        column, value = change.first
        expect_refused { connection.execute("UPDATE #{model.table_name} SET #{column} = #{connection.quote(value)} WHERE id = #{event.id}") }
        expect_refused { connection.execute("DELETE FROM #{model.table_name} WHERE id = #{event.id}") }
        expect(model.find(event.id).attributes).to eq(original)
      end
    end
  end
end
