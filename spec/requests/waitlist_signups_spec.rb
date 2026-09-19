require "rails_helper"

RSpec.describe "Waitlist signups" do
  def join_with(email, website: nil)
    post waitlist_signup_path, params: {
      waitlist_signup: { email: email, website: website }
    }
  end

  it "shows the landing page to a signed-out visitor" do
    open_the_waitlist

    get root_path

    expect(response.body).to include("Your news feed")
  end

  # Opening the app should land on the day's briefing, not on a page selling
  # it. The edition is the app; the originals are an archive behind it.
  it "sends a signed-in reader to the latest edition" do
    sign_in
    create(:edition, published_on: Date.new(2026, 8, 11))
    today = create(:edition, published_on: Date.new(2026, 8, 12))

    get root_path

    expect(response).to redirect_to(edition_url(today))
  end

  # Day one, and any morning after a run that found nothing to compose: there
  # is no edition to serve. The archive is the page that says when to expect
  # one, which is a better answer than the inbox the edition replaced.
  it "sends a signed-in reader to the archive before there is an edition" do
    sign_in

    get root_path

    expect(response).to redirect_to(editions_url)
  end

  # The one page in this app meant to be found. Everything behind the sign-in
  # gate keeps the noindex tag the layout emits by default.
  it "lets the landing page be indexed" do
    open_the_waitlist

    get root_path

    expect(response.body).not_to include(%(name="robots"))
  end

  it "adds an address to the waitlist" do
    open_the_waitlist

    join_with("reader@example.com")

    expect(WaitlistSignup.pluck(:email)).to eq([ "reader@example.com" ])
  end

  it "replaces the form with the success state in place" do
    open_the_waitlist

    join_with("reader@example.com")

    expect(response.body).to include("On the list")
  end

  it "shows the address that joined" do
    open_the_waitlist

    join_with("reader@example.com")

    expect(response.body).to include("reader@example.com")
  end

  # Both instances switch together, or the page shows a form and a
  # confirmation for the same address at once.
  it "switches both form instances over a Turbo Stream" do
    open_the_waitlist

    post waitlist_signup_path,
      params: { waitlist_signup: { email: "reader@example.com" } },
      as: :turbo_stream

    expect(response.body).to include("waitlist-hero").and include("waitlist-band")
  end

  it "reports success for an address already on the list" do
    open_the_waitlist
    create(:waitlist_signup, email: "reader@example.com")

    join_with("reader@example.com")

    expect(response.body).to include("On the list")
  end

  it "keeps one row for an address that joins twice" do
    open_the_waitlist
    create(:waitlist_signup, email: "reader@example.com")

    join_with("reader@example.com")

    expect(WaitlistSignup.count).to eq(1)
  end

  it "asks again when the address is not one" do
    open_the_waitlist

    join_with("not-an-address")

    expect(response).to have_http_status(422)
  end

  it "records nothing when the address is not one" do
    open_the_waitlist

    join_with("not-an-address")

    expect(WaitlistSignup.count).to eq(0)
  end

  it "records nothing when the honeypot has been filled" do
    open_the_waitlist

    join_with("bot@example.com", website: "https://spam.example")

    expect(WaitlistSignup.count).to eq(0)
  end

  # Answering a bot with a 422 would tell it which field caught it.
  it "answers a filled honeypot exactly as it answers a real signup" do
    open_the_waitlist

    join_with("bot@example.com", website: "https://spam.example")

    expect(response.body).to include("On the list")
  end

  it "turns away a visitor signing up over and over" do
    open_the_waitlist

    6.times { |index| join_with("reader#{index}@example.com") }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "needs no sign-in to reach the waitlist" do
    open_the_waitlist

    join_with("reader@example.com")

    expect(response).not_to redirect_to(new_session_path)
  end

  # Off is the default a self-hoster gets: their instance has no waitlist to
  # join, so the front door is the sign-in page.
  it "sends a signed-out visitor to sign in while the waitlist is closed" do
    close_the_waitlist

    get root_path

    expect(response).to redirect_to(new_session_url)
  end

  it "answers 404 to a signup while the waitlist is closed" do
    close_the_waitlist

    join_with("reader@example.com")

    expect(response).to have_http_status(:not_found)
  end

  it "records nothing for a signup while the waitlist is closed" do
    close_the_waitlist

    join_with("reader@example.com")

    expect(WaitlistSignup.count).to eq(0)
  end

  # The 404 has to come before the rate limiter, or a closed waitlist still
  # counts signups and answers the sixth with a 429 that says it is open. One
  # post passes either way; only the sixth tells the two orders apart.
  it "answers 404 rather than 429 to a sixth signup while the waitlist is closed" do
    close_the_waitlist

    6.times { |index| join_with("reader#{index}@example.com") }

    expect(response).to have_http_status(:not_found)
  end

  it "keeps sending a signed-in reader to the edition while the waitlist is closed" do
    close_the_waitlist
    sign_in
    edition = create(:edition, published_on: Date.new(2026, 8, 12))

    get root_path

    expect(response).to redirect_to(edition_url(edition))
  end
end
