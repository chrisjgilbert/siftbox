require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "shoulda/matchers"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |file| require file }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActionMailbox::TestHelper, type: :mailbox
  # For the jobs that retry: perform_enqueued_jobs runs the retry the way the
  # worker would, so a spec can count what a failing job actually costs rather
  # than read the number off its own declaration.
  config.include ActiveJob::TestHelper, type: :job
  config.include ActiveSupport::Testing::TimeHelpers

  # The waitlist's rate limit counts in Rails.cache, which the test
  # environment keeps in memory for the whole run. Without this, one example
  # exhausting the limit answers 429 to every example after it.
  config.before { Rails.cache.clear }
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
