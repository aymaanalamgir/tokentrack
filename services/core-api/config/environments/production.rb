Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
  config.i18n.fallbacks = true
  # Opt in behind a TLS-terminating proxy. This slice runs on local HTTP.
  config.force_ssl = ENV.fetch("FORCE_SSL", "false") == "true"
  config.assume_ssl = config.force_ssl
end
