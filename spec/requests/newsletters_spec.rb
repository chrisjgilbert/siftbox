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

    expect(response.body).to include("Unread (1)")
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

  it "drops the separator along with the missing domain" do
    sign_in
    create(:newsletter, sender_name: "", sender_email: "", subject: "No sender")

    get newsletters_path

    expect(response.body).not_to include("row__domain")
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

    expect(response.body).not_to include("neighbours__title")
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
