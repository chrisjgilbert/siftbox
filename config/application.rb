require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Newsbox
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # The feed groups by calendar day and labels rows with wall-clock times,
    # so leaving this at UTC files the reader's late-evening mail under the
    # wrong heading and shows every timestamp in the wrong zone.
    config.time_zone = ENV.fetch("NEWSBOX_TIME_ZONE", "London")

    # The address subscriptions are pointed at. Shown in the feed header and
    # the empty state. Placeholder until the inbound domain is decided.
    config.x.inbound_address =
      ENV.fetch("NEWSBOX_INBOUND_ADDRESS", "newsletters@example.com")

    config.action_mailer.preview_paths << Rails.root.join("spec/mailers/previews")

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
