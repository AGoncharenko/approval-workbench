# Company-wide audit history reads newest first; role_change_events got the same index when it was created.
class AddCompanyHistoryIndexToApprovalEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :approval_events, "company_id, created_at DESC", name: "index_approval_events_on_company_history"
  end
end
