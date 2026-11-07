abort("Cannot run specs in production") if ENV["RAILS_ENV"] == "production"
# Compose sets development for the web process; specs must always use the isolated test DB.
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("Cannot run specs in production") if Rails.env.production?
require "rspec/rails"

RSpec.configure do |config|
  # No domain tables exist; request specs exercise the real connection without fixtures.
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
