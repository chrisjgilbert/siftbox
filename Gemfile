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

# What Active Storage's image analyser needs. See Newsletter::ImageDimensions
# for why the app wants the sizes it measures. Named directly because nothing
# else brings it: this app builds no variants, so it does not bundle
# image_processing, and Active Storage logs one warning a boot saying so.
#
# Do not take that warning's second suggestion. `variant_processor = :disabled`
# silences it and silently stops every image being measured — the Vips
# analyser only accepts a blob while the processor is :vips.
#
# 2.2.1 because Active Storage raises unless ruby-vips answers
# `block_untrusted`, added in that version, and the raise is a bare
# RuntimeError its LoadError handler does not catch. Nothing else in the graph
# sets a floor, so a resolution below it installs cleanly and then cannot
# boot. The control is live here rather than a formality: this app measures
# images that arrive by email and images it fetches from the web.
#
# require: false so Bundler does not require it at boot. Active Storage
# requires it first and inside a rescue, and carries on without sizes when
# libvips is missing; Bundler's require is unguarded and would take the
# process down instead — which is what happened to the JavaScript audit job,
# whose runner has no reason to carry the library.
gem "ruby-vips", ">= 2.2.1", "< 3", require: false

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
  gem "shoulda-matchers", "~> 6.4"
  gem "webmock", "~> 3.24"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

gem "honeybadger", "~> 6.9"
