abort("Cannot run specs in production") if ENV["RAILS_ENV"] == "production"
# Compose sets development for the web process; specs must always use the isolated test DB.
ENV["RAILS_ENV"] = "test"
ENV["DEMO_AUTH_ENABLED"] = "true"
require_relative "../config/environment"
abort("Cannot run specs in production") if Rails.env.production?
require "rspec/rails"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.before(:suite) do
    ActiveRecord::Migration.check_all_pending!
    DemoData.seed!
  end
  Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |file| require file }
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
