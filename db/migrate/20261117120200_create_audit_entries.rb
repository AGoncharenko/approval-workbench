# One read-only history over both audit tables. Update this view whenever either table changes shape.
# Role changes are made only by admins (ChangeUserRole re-checks the actor under the lock), so their actor_role is 'admin'.
class CreateAuditEntries < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIEW audit_entries AS
        SELECT 'transition'::text AS kind, company_id, actor_id, actor_role::text, invoice_id, NULL::bigint AS target_user_id,
               action::text, from_status::text AS from_value, to_status::text AS to_value, reason, created_at, id AS source_id
          FROM approval_events
        UNION ALL
        SELECT 'role_change'::text, company_id, actor_id, 'admin'::text, NULL::bigint, target_user_id,
               'role_change'::text, from_role::text, to_role::text, NULL::text, created_at, id
          FROM role_change_events;
    SQL
  end

  def down
    execute "DROP VIEW audit_entries"
  end
end
