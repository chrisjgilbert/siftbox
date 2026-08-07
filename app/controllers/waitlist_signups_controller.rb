# The landing page and the waitlist behind it — the only part of this app a
# signed-out visitor can reach, and the only public write path on the
# internet.
class WaitlistSignupsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]

  # A honeypot rather than a captcha handles the bots that read the form; this
  # handles the ones that do not. Rails 8's rate limiter counts in Rails.cache,
  # which is Solid Queue's database-backed store in production, so the count is
  # shared across Puma workers rather than per process.
  rate_limit to: 5, within: 1.minute, only: :create

  def new
    return redirect_to newsletters_url if authenticated?

    @waitlist_signup = WaitlistSignup.new
  end

  def create
    @waitlist_signup = WaitlistSignup.new(waitlist_signup_params)

    if @waitlist_signup.join
      render :create
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def waitlist_signup_params
    params.expect(waitlist_signup: [ :email, :website ])
  end
end
