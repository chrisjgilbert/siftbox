source "https://rubygems.org"

ruby "3.3.6"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Known vulnerabilities in bundled gems [https://github.com/rubysec/bundler-audit]
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Cops the house rules call out by name, in .claude/rules/review.md
  gem "rubocop-rspec", require: false
  gem "rubocop-thread_safety", require: false

  gem "factory_bot_rails", "~> 6.4"
  gem "rspec-rails", "~> 7.1"
end

group :test do
  # Reads a rendered page the way a reader does, by accessible name and role,
  # which .claude/rules/testing.md asks of anything above a request spec.
  # Driven by rack_test — nothing on these pages needs JavaScript, so no
  # browser and no driver gem.
  gem "capybara", "~> 3.40"
  gem "shoulda-matchers", "~> 6.4"
  gem "webmock", "~> 3.26"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "honeybadger", "~> 6.9"

# The model that writes the edition [https://github.com/anthropics/anthropic-sdk-ruby]
gem "anthropic", "~> 1.72"

# Reads the blogs' RSS and Atom feeds [https://github.com/ruby/rss]. A bundled
# gem rather than a default one, so it has to be declared here or `require
# "rss"` raises under Bundler. It brings rexml with it, which until now was a
# test-only dependency of webmock's.
#
# Pinned to the patch line rather than the usual pessimistic minor. Blog::Feed
# reads this gem's element shapes directly — which classes answer #content
# against #href, which answer content_encoded or dc_date, that #link is one
# element and #links is a list — and none of that is documented API on a
# pre-1.0 gem, so a minor bump wants a person rather than a bundle update.
gem "rss", "~> 0.3.3"
