Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :null_store
  config.active_support.deprecation = :log
  # A database outage must reach the health controller, not fail in migration middleware.
  # Run db:migrate explicitly when adding migrations in later slices.
  config.active_record.migration_error = false
  config.active_record.verbose_query_logs = true
  config.hosts << "core-api"
end
