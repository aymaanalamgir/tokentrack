Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :null_store
  config.active_support.deprecation = :log
  # A database outage must reach the health controller, not fail in migration middleware.
  # Run db:migrate explicitly when adding migrations in later slices.
  config.active_record.migration_error = false
  # Compose defaults RAILS_LOG_LEVEL to info: debug SQL logging writes hundreds of MB to the bind-mounted log
  # during a demo load. Set RAILS_LOG_LEVEL=debug to trace queries.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug").to_sym
  config.active_record.verbose_query_logs = config.log_level == :debug
  config.hosts << "core-api"
end
