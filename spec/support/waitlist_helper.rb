# The landing page and the waitlist behind it are switched on per deployment
# by config.x.waitlist, which is read from the environment once at boot. A
# spec cannot flip it by setting the variable, so it stubs the configuration
# instead. Every example that reaches the landing page or posts a signup says
# which state it wants, so a variable set in CI can never change what an
# example tests. The custom configuration object answers respond_to? for any
# name, which is what lets the stub through verify_partial_doubles.
module WaitlistHelper
  def open_the_waitlist
    allow(Rails.configuration.x).to receive(:waitlist).and_return(true)
  end

  def close_the_waitlist
    allow(Rails.configuration.x).to receive(:waitlist).and_return(false)
  end
end

RSpec.configure do |config|
  config.include WaitlistHelper, type: :request
  config.include WaitlistHelper, type: :system
end
