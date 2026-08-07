require "rails_helper"

RSpec.describe "Newsletters" do
  it "sends a signed-out reader to the sign-in page" do
    create(:newsletter)

    get newsletters_path

    expect(response).to redirect_to(new_session_path)
  end

  it "lists the newsletters in the feed" do
    sign_in
    create(:newsletter, subject: "Ruby 3.4 lands")

    get newsletters_path

    expect(response.body).to include("Ruby 3.4 lands")
  end

  it "shows the unread count in the filter bar" do
    sign_in
    create(:newsletter, read_at: nil)

    get newsletters_path

    expect(response.body).to include("Unread [1]")
  end

  it "hides read newsletters when filtered to unread" do
    sign_in
    create(:newsletter, subject: "Already read", read_at: 1.hour.ago)
    create(:newsletter, subject: "Not yet read", read_at: nil)

    get newsletters_path(filter: "unread")

    expect(response.body).not_to include("Already read")
  end

  it "keeps unread newsletters when filtered to unread" do
    sign_in
    create(:newsletter, subject: "Already read", read_at: 1.hour.ago)
    create(:newsletter, subject: "Not yet read", read_at: nil)

    get newsletters_path(filter: "unread")

    expect(response.body).to include("Not yet read")
  end

  it "renders the newsletter body in the reader" do
    sign_in
    newsletter = create(:newsletter, body_html: "<p>Ruby 3.4 is out</p>")

    get newsletter_path(newsletter)

    expect(response.body).to include("<p>Ruby 3.4 is out</p>")
  end

  it "strips the sender's styling from the reader" do
    sign_in
    newsletter = create(:newsletter, body_html: %(<p style="color:red">Hi</p>))

    get newsletter_path(newsletter)

    expect(response.body).not_to include("color:red")
  end

  # Without the guard this row reads "—" with nothing either side.
  it "shows no dangling separator for a newsletter with no sender at all" do
    sign_in
    create(:newsletter, sender_name: "", sender_email: "", subject: "No sender")

    get newsletters_path

    expect(response.body).to include("Unknown sender")
  end

  # The feed row carries the sender alone. The domain moved to the reader's
  # kicker, which has the room for it.
  it "leaves the sender domain off the feed row" do
    sign_in
    create(:newsletter, sender_name: "Ruby Weekly", sender_email: "peter@rubyweekly.com")

    get newsletters_path

    expect(response.body).not_to include("rubyweekly.com")
  end

  it "numbers the feed rows" do
    sign_in
    create(:newsletter, received_at: 1.hour.ago)
    create(:newsletter, received_at: 2.hours.ago)

    get newsletters_path

    expect(response.body).to include(">01<").and include(">02<")
  end

  it "leads the feed with the newest newsletter when it has an image" do
    sign_in
    create(:newsletter, lead_image_url: "https://cdn.example/hero.png")

    get newsletters_path

    expect(response.body).to include("lead__image")
  end

  it "falls back to a standard row when the newest newsletter has no image" do
    sign_in
    create(:newsletter, lead_image_url: "")

    get newsletters_path

    expect(response.body).not_to include("lead__image")
  end

  # The dashed box keeps the right edge aligned when a newsletter carries no
  # image, so the rows around it do not go ragged.
  it "shows the fallback box for a row with no image" do
    sign_in
    create(:newsletter, lead_image_url: "https://cdn.example/hero.png")
    create(:newsletter, lead_image_url: "", received_at: 2.hours.ago)

    get newsletters_path

    expect(response.body).to include("No image in email")
  end

  it "counts the issues at the end of the feed" do
    sign_in
    create(:newsletter)
    create(:newsletter, received_at: 2.hours.ago)

    get newsletters_path

    expect(response.body).to include("End of feed — 2 issues")
  end

  # The address used to sit in the header. The redesign puts the brand there
  # instead, so the end-of-feed note is where a subscription gets pointed.
  it "names the inbound address at the end of the feed" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.body).to include("Subscribe with newsletters@example.com")
  end

  it "links to the newer neighbour from the reader" do
    sign_in
    create(:newsletter, received_at: 2.days.ago)
    newer = create(:newsletter, received_at: 1.day.ago, subject: "The later one")

    get newsletter_path(Newsletter.order(:received_at).first)

    expect(response.body).to include(newsletter_path(newer))
  end

  it "links to the older neighbour from the reader" do
    sign_in
    older = create(:newsletter, received_at: 2.days.ago, subject: "The earlier one")
    create(:newsletter, received_at: 1.day.ago)

    get newsletter_path(Newsletter.order(:received_at).last)

    expect(response.body).to include("The earlier one")
  end

  it "renders the reader without neighbour links when it is the only newsletter" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_path(newsletter)

    expect(response.body).not_to include("neighbours__subject")
  end

  it "heads the reader with the sender and the source domain" do
    sign_in
    newsletter = create(:newsletter, sender_name: "Ruby Weekly",
      sender_email: "peter@rubyweekly.com")

    get newsletter_path(newsletter)

    expect(response.body).to include("Ruby Weekly / rubyweekly.com")
  end

  it "stamps the received time in the reader's data strip" do
    sign_in
    newsletter = create(:newsletter, received_at: Time.zone.parse("2026-08-05 09:02"))

    get newsletter_path(newsletter)

    expect(response.body).to include("Received 2026.08.05 09:02")
  end

  it "shows the issue number when the subject carries one" do
    sign_in
    newsletter = create(:newsletter, subject: "#742: A faster CSV parser")

    get newsletter_path(newsletter)

    expect(response.body).to include("Issue 742")
  end

  it "leaves the issue field out when the subject carries no number" do
    sign_in
    newsletter = create(:newsletter, subject: "Five articles worth your evening")

    get newsletter_path(newsletter)

    expect(response.body).not_to include("Issue ")
  end

  it "estimates the reading time in the data strip" do
    sign_in
    newsletter = create(:newsletter, body_html: "<p>#{Array.new(600, 'word').join(' ')}</p>")

    get newsletter_path(newsletter)

    expect(response.body).to include("3 min")
  end

  it "promotes the first image above the article" do
    sign_in
    newsletter = create(:newsletter, lead_image_url: "https://cdn.example/hero.png",
      body_html: %(<img src="https://cdn.example/hero.png"><p>Morning</p>))

    get newsletter_path(newsletter)

    expect(response.body).to include("leadshot__image")
  end

  # Promoting it means taking it out of the body. Rendering both is the bug
  # this guards.
  it "renders the promoted image once rather than twice" do
    sign_in
    newsletter = create(:newsletter, lead_image_url: "https://cdn.example/hero.png",
      body_html: %(<img src="https://cdn.example/hero.png"><p>Morning</p>))

    get newsletter_path(newsletter)

    expect(response.body.scan("cdn.example/hero.png").length).to eq(1)
  end

  it "omits the lead image block for a newsletter with no images" do
    sign_in
    newsletter = create(:newsletter, lead_image_url: "", body_html: "<p>Morning</p>")

    get newsletter_path(newsletter)

    expect(response.body).not_to include("leadshot__image")
  end

  it "marks a newsletter read when it is opened" do
    sign_in
    newsletter = create(:newsletter, read_at: nil)

    get newsletter_path(newsletter)

    expect(newsletter.reload).to be_read
  end

  # Turbo prefetches on hover. Opening a newsletter writes, so a prefetch
  # would mark a feed row read without the reader opening it.
  it "turns off Turbo's hover prefetching" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.body).to include(%(<meta name="turbo-prefetch" content="false">))
  end

  # The layout no longer emits this unconditionally — the landing page opts
  # out so it can be found. Everything behind the sign-in gate keeps it.
  it "keeps the feed out of search indexes" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.body).to include(%(<meta name="robots" content="noindex, nofollow">))
  end

  it "keeps the reader out of search indexes" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_path(newsletter)

    expect(response.body).to include(%(<meta name="robots" content="noindex, nofollow">))
  end

  # Hotlinked newsletter images are cross-origin requests, and the browser
  # default sends this app's origin in the Referer header with each one —
  # telling every sender's image host where the archive lives.
  it "keeps the app's origin out of requests to newsletter image hosts" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_path(newsletter)

    expect(response.body).to include(%(<meta name="referrer" content="same-origin">))
  end

  it "marks a newsletter unread again on request" do
    sign_in
    newsletter = create(:newsletter, read_at: 1.hour.ago)

    delete newsletter_read_path(newsletter)

    expect(newsletter.reload).not_to be_read
  end

  it "frames the sender's own HTML on the view-original screen" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_original_path(newsletter)

    expect(response.body).to include(newsletter_source_path(newsletter))
  end

  it "sandboxes the frame without allowing scripts or same-origin access" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_original_path(newsletter)

    expect(response.body).to include(
      %(sandbox="allow-popups allow-popups-to-escape-sandbox")
    )
  end

  it "serves the source HTML with the sender's styling intact" do
    sign_in
    newsletter = create(:newsletter, body_html: %(<p style="color:red">Hi</p>))

    get newsletter_source_path(newsletter)

    expect(response.body).to include(%(style="color:red"))
  end

  it "locks the source HTML down with its own content security policy" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_source_path(newsletter)

    expect(response.headers["Content-Security-Policy"]).to include("default-src 'none'")
  end

  it "keeps a signed-out reader away from the source HTML" do
    newsletter = create(:newsletter)

    get newsletter_source_path(newsletter)

    expect(response).to redirect_to(new_session_path)
  end

  it "keeps a signed-out reader out of the reader view" do
    newsletter = create(:newsletter)

    get newsletter_path(newsletter)

    expect(response).to redirect_to(new_session_path)
  end

  it "keeps a signed-out reader off the view-original screen" do
    newsletter = create(:newsletter)

    get newsletter_original_path(newsletter)

    expect(response).to redirect_to(new_session_path)
  end

  it "keeps a signed-out visitor from changing read state" do
    newsletter = create(:newsletter, read_at: 1.hour.ago)

    delete newsletter_read_path(newsletter)

    expect(newsletter.reload).to be_read
  end

  it "sends the reader back to the feed after marking unread" do
    sign_in
    newsletter = create(:newsletter, read_at: 1.hour.ago)

    delete newsletter_read_path(newsletter)

    expect(response).to redirect_to(newsletters_url)
  end

  it "sandboxes the source response itself, not just the frame around it" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_source_path(newsletter)

    expect(response.headers["Content-Security-Policy"]).to include("sandbox allow-popups")
  end

  it "lets the source view load the inline images it stored" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_source_path(newsletter)

    expect(response.headers["Content-Security-Policy"]).to include("img-src 'self'")
  end

  it "sends a content security policy with the reader view" do
    sign_in
    newsletter = create(:newsletter)

    get newsletter_path(newsletter)

    expect(response.headers["Content-Security-Policy"]).to include("object-src 'none'")
  end
end
