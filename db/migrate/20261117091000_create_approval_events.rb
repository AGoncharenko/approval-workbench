class CreateApprovalEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_events do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.bigint :invoice_id, null: false
      t.references :actor, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :actor_role, null: false
      t.string :action, null: false
      t.string :from_status, null: false
      t.string :to_status, null: false
      t.text :reason
      t.datetime :created_at, null: false, default: -> { "now()" }
      # submit is listed so add-invoice-submission needs no schema change.
      t.check_constraint "action IN ('submit', 'approve', 'reject')", name: "approval_events_action_allowed"
      t.check_constraint "actor_role IN ('requester', 'approver', 'admin')", name: "approval_events_actor_role_allowed"
      t.check_constraint "from_status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED')", name: "approval_events_from_status_allowed"
      t.check_constraint "to_status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED')", name: "approval_events_to_status_allowed"
      t.check_constraint "reason IS NULL OR char_length(reason) BETWEEN 1 AND 1000", name: "approval_events_reason_length"
    end
    add_index :approval_events, [ :company_id, :invoice_id, :created_at ], name: "index_approval_events_on_invoice_history"
    # Composite FK: an event can only point at an invoice of its own company.
    add_foreign_key :approval_events, :invoices, column: [ :company_id, :invoice_id ], primary_key: [ :company_id, :id ],
      name: "approval_events_invoice_same_company"
  end
end
