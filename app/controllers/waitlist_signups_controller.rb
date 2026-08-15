# The landing page and the waitlist behind it — the only part of this app a
# signed-out visitor can reach, and the only public write path on the
# internet.
class WaitlistSignupsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]

  # A honeypot rather than a captcha handles the bots that read the form; this
  # handles the ones that do not. Rails 8's rate limiter counts in Rails.cache,
  # which is Solid Queue's database-backed store in production, so the count is
  # shared across Puma workers rather than per process.
  rate_limit to: 5, within: 1.minute, only: :create, with: -> { too_many_signups }

  def new
    return redirect_to reader_home_url if authenticated?

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

  # Home for a signed-in reader is the day's briefing: root serves the latest
  # edition, and the originals are an archive behind it rather than the first
  # thing the app shows.
  #
  # Before the first edition is composed there is nothing to serve, and the
  # editions archive is where the app says when to expect one. Sending a
  # reader to the inbox instead would make the empty morning look like the
  # design. Read through for_archive because a redirect wants an id, not the
  # model's whole answer in raw_response.
  def reader_home_url
    edition = Edition.for_archive.latest
    return editions_url unless edition

    edition_url(edition)
  end

  # Rails answers a bare `head :too_many_requests` by default, and Turbo drops
  # a response carrying no body — the submit button would simply stop doing
  # anything. Rendering the page back gives Turbo something to swap in.
  def too_many_signups
    @waitlist_signup = WaitlistSignup.new

    render :new, status: :too_many_requests
  end

  def waitlist_signup_params
    params.expect(waitlist_signup: [ :email, :website ])
  end
end
