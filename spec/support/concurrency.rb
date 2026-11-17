# Tag a group with :concurrency when its threads need to see each other's
# committed rows: it runs outside the per-example transaction and truncates after.
RSpec.configure do |config|
  # A hook, not a shared context: rspec-rails' FixtureSupport is included later and would reset the flag to true.
  config.before(:context, :concurrency) { self.class.use_transactional_tests = false }

  config.after(:each, :concurrency) do
    ActiveRecord::Base.connection_pool.with_connection do |conn|
      conn.truncate_tables(*(conn.tables - %w[schema_migrations ar_internal_metadata]))
    end
  end
end
