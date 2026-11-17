require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Render terminates TLS at its edge. Both default to true; compose on plain-HTTP localhost sets them to "false".
  # The /up exemption from the HTTPS redirect is in config/application.rb so a spec can exercise it.
  config.assume_ssl = ENV.fetch("RAILS_ASSUME_SSL", "true") != "false"
  config.force_ssl = ENV.fetch("RAILS_FORCE_SSL", "true") != "false"

  # Log to STDOUT (Render's Logs view); the request id tag is set in config/application.rb.
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Only serve our own host names, so redirects built from the Host header (root_url, return_to) can't be poisoned.
  # Render sets RENDER_EXTERNAL_HOSTNAME; compose and local runs use localhost. /up stays open for Render's probe.
  config.hosts = [ "localhost", "127.0.0.1", ENV["RENDER_EXTERNAL_HOSTNAME"] ].compact
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Render serves through Cloudflare, so the nearest untrusted hop in X-Forwarded-For is a Cloudflare edge, not the
  # visitor. Trusting Cloudflare's published ranges (cloudflare.com/ips, fetched 2026-11-17) makes request.remote_ip
  # the visitor's address, which the sign-in rate limit, session records and logs rely on.
  config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18
    190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { IPAddr.new(it) }
end
