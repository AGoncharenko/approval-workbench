# Audit events are append-only below the application: update_all, delete_all and raw SQL are refused too.
# TRUNCATE is not blocked (it needs table-owner rights; test cleanup uses it).
class AddAuditAppendOnlyTriggers < ActiveRecord::Migration[8.1]
  TABLES = %w[approval_events role_change_events].freeze

  def up
    execute <<~SQL
      CREATE FUNCTION forbid_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION '% on % is not allowed: audit events are append-only', TG_OP, TG_TABLE_NAME
          USING ERRCODE = 'insufficient_privilege';
      END
      $$;
    SQL
    TABLES.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_append_only BEFORE UPDATE OR DELETE ON #{table}
          FOR EACH ROW EXECUTE FUNCTION forbid_audit_mutation();
      SQL
    end
  end

  def down
    TABLES.each { execute "DROP TRIGGER #{it}_append_only ON #{it}" }
    execute "DROP FUNCTION forbid_audit_mutation()"
  end
end
