# Tag a group with :concurrency when its threads need to see each other's
# committed rows: it runs outside the per-example transaction and truncates after.
RSpec.shared_context "concurrency", :concurrency do
  self.use_transactional_tests = false

  after do
    ActiveRecord::Base.connection_pool.with_connection do |conn|
      conn.truncate_tables(*(conn.tables - %w[schema_migrations ar_internal_metadata]))
    end
  end
end
