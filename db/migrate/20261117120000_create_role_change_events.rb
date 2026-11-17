class CreateRoleChangeEvents < ActiveRecord::Migration[8.1]
  def change
    # Target for composite FKs from child tables, so they cannot reference another tenant's user.
    add_index :users, [ :company_id, :id ], unique: true

    create_table :role_change_events do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.references :actor, null: false
      t.references :target_user, null: false
      t.string :from_role, null: false
      t.string :to_role, null: false
      t.datetime :created_at, null: false, default: -> { "now()" }
      t.check_constraint "from_role IN ('requester', 'approver', 'admin')", name: "role_change_events_from_role_allowed"
      t.check_constraint "to_role IN ('requester', 'approver', 'admin')", name: "role_change_events_to_role_allowed"
      t.check_constraint "from_role <> to_role", name: "role_change_events_role_changed"
    end
    add_index :role_change_events, "company_id, created_at DESC", name: "index_role_change_events_on_company_history"
    # Composite FKs: both users must belong to the event's company. RESTRICT keeps users with history from being deleted.
    add_foreign_key :role_change_events, :users, column: [ :company_id, :actor_id ], primary_key: [ :company_id, :id ],
      on_delete: :restrict, name: "role_change_events_actor_same_company"
    add_foreign_key :role_change_events, :users, column: [ :company_id, :target_user_id ], primary_key: [ :company_id, :id ],
      on_delete: :restrict, name: "role_change_events_target_same_company"
  end
end
