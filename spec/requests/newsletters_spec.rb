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

  it "counts the items at the end of the feed" do
    sign_in
    create(:newsletter)
    create(:newsletter, received_at: 2.hours.ago)

    get newsletters_path

    expect(response.body).to include("End of feed — 2 items")
  end

  def fill(count)
    Array.new(count) { |n| create(:newsletter, subject: "Issue #{n}", received_at: n.hours.ago) }
  end

  it "offers a way back when the archive holds more than a page" do
    sign_in
    fill(Feed::Page::SIZE + 1)

    get newsletters_path

    expect(response.body).to include("Older")
  end

  it "offers no way back when the archive fits on one page" do
    sign_in
    fill(Feed::Page::SIZE)

    get newsletters_path

    expect(response.body).not_to include("Older")
  end

  it "carries on below the row the way back names" do
    sign_in
    issues = fill(Feed::Page::SIZE + 1)

    get newsletters_path(after_kind: "Newsletter", after_id: issues[Feed::Page::SIZE - 1].id)

    expect(response.body).to include(issues.last.subject)
    expect(response.body).not_to include(issues.first.subject)
  end

  # The end note marks the end of the archive, so it waits until there is
  # nothing below. On a first page of many it would be a full stop in the
  # middle of a sentence.
  it "holds the end note back while there is another page" do
    sign_in
    fill(Feed::Page::SIZE + 1)

    get newsletters_path

    expect(response.body).not_to include("End of feed")
  end

  # Everything the archive holds, not everything this page drew. A last page
  # of twelve under a line reading "12 items" would put a number on the
  # archive that is off by every page before it.
  it "counts the whole archive at the end of the last page" do
    sign_in
    issues = fill(Feed::Page::SIZE + 1)

    get newsletters_path(after_kind: "Newsletter", after_id: issues[Feed::Page::SIZE - 1].id)

    expect(response.body).to include("End of feed — #{Feed::Page::SIZE + 1} items")
  end

  # An address the reader edited, or a link to a row since removed. The first
  # page is the honest answer, rather than a 404 on an archive.
  it "answers with the first page for a cursor naming a row that has gone" do
    sign_in
    create(:newsletter, subject: "Still here")

    get newsletters_path(after_kind: "Newsletter", after_id: 0)

    expect(response.body).to include("Still here")
  end

  # The kind names a class the cursor then loads from, so it is matched
  # against the two the archive holds and nothing else.
  it "ignores a cursor naming a kind the archive does not hold" do
    sign_in
    create(:newsletter, subject: "Still here")

    get newsletters_path(after_kind: "User", after_id: 1)

    expect(response.body).to include("Still here")
  end

  # With nothing to show there is no end-of-feed note, so this is the only
  # place left that says where to point a subscription.
  it "tells a reader with an empty feed where to point a subscription" do
    sign_in

    get newsletters_path

    expect(response.body).to include("Point a subscription at newsletters@example.com")
  end

  it "shows no end-of-feed note when there is no feed" do
    sign_in

    get newsletters_path

    expect(response.body).not_to include("End of feed")
  end

  # The address used to sit in the header. The redesign puts the brand there
  # instead, so the end-of-feed note is where a subscription gets pointed.
  it "names the inbound address at the end of the feed" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.body).to include("Subscribe with newsletters@example.com")
  end

  # Nothing writes on a GET any more, so this is bandwidth rather than
  # correctness: an archive row points at an original, and prefetching one on
  # hover would pull a body that runs to hundreds of kilobytes, plus whatever
  # images it references, for a row the reader only passed over.
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

  # Hotlinked newsletter images are cross-origin requests, and the browser
  # default sends this app's origin in the Referer header with each one —
  # telling every sender's image host where the archive lives.
  it "keeps the app's origin out of requests to newsletter image hosts" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.body).to include(%(<meta name="referrer" content="same-origin">))
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

  it "keeps a signed-out reader off the view-original screen" do
    newsletter = create(:newsletter)

    get newsletter_original_path(newsletter)

    expect(response).to redirect_to(new_session_path)
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

  it "sends a content security policy with the archive" do
    sign_in
    create(:newsletter)

    get newsletters_path

    expect(response.headers["Content-Security-Policy"]).to include("object-src 'none'")
  end

  it "lists blog posts in the same feed as the newsletters" do
    sign_in
    create(:newsletter, subject: "Ruby 3.4 lands", received_at: 2.hours.ago)
    create(:blog_post, title: "Why your index is not used", received_at: 1.hour.ago)

    get newsletters_path

    expect(response.body).to include("Why your index is not used")
  end

  # The row's own line says which it is, so the reader can tell before
  # clicking whether it opens an email or somebody's website.
  it "marks a blog post as one" do
    sign_in
    create(:blog_post, title: "Why your index is not used")

    get newsletters_path

    expect(response.body).to include("row__kind")
  end

  # A post's original is the blog, which is somebody else's site — so the link
  # leaves the app, and leaves it without handing the opened page a reference
  # back through window.opener.
  it "sends a blog post's row to the blog, in a new tab" do
    sign_in
    create(:blog_post, url: "https://queryplanweekly.dev/unused-index")

    get newsletters_path

    expect(response.body).to include('href="https://queryplanweekly.dev/unused-index"')
      .and include('rel="noopener noreferrer"')
  end

  it "says a post with no image carried none, rather than calling it an email" do
    sign_in
    create(:blog_post, lead_image_url: "", received_at: 1.hour.ago)

    get newsletters_path

    expect(response.body).to include("No image in post")
    expect(response.body).not_to include("No image in email")
  end

  # The newest item having an image is what makes it the lead, and a post with
  # an image is an ordinary case — so the one row drawn at full frame width
  # was the one row that lost its marker.
  it "marks a post that leads the feed as a post" do
    sign_in
    create(:blog_post, lead_image_url: "https://queryplanweekly.dev/hero.png",
      received_at: 1.hour.ago)

    get newsletters_path

    expect(response.body).to include("lead__kind")
  end
end
