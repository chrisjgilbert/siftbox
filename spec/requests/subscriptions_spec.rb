require "rails_helper"

RSpec.describe "Subscriptions" do
  def pen_of(rows)
    rows.times do |index|
      create(:newsletter, sender_email: "sender#{index}@substack.com",
        held_at: 1.hour.ago)
    end
  end

  # The pen lists senders and subjects out of the reader's own mail, which is
  # the whole of what the gate is protecting.
  it "keeps a signed-out reader away from the pen" do
    create(:newsletter, held_at: 1.hour.ago)

    get subscriptions_path

    expect(response).to redirect_to(new_session_path)
  end

  # Every row prints a sender, a subject and a time. Reading a body to print
  # none of it is what Newsletter::PEN_COLUMNS exists to stop, and the page
  # draws two sections of rows out of one table.
  it "renders a pen row without reading the newsletter's body" do
    sign_in
    create(:newsletter, subject: "Confirm your subscription",
      body_html: "<p>#{'Morning. ' * 200}</p>", held_at: 1.hour.ago)

    get subscriptions_path

    expect(response.body).to include("Confirm your subscription")
    expect(response.body).not_to include("Morning. Morning.")
  end

  # Three sections, three queries, however much is in them. The first request
  # is thrown away because Rails caches the schema and the templates on it.
  # What is held here is that the cost does not move with the size of the pen;
  # the absolute number belongs to Rails.
  it "draws a pen of any size in the same number of queries" do
    sign_in
    pen_of(1)
    get subscriptions_path
    quiet = count_queries { get subscriptions_path }

    pen_of(5)

    expect(count_queries { get subscriptions_path }).to eq(quiet)
  end

  # The roster used to read one COUNT per blog to print "12 posts". What is
  # held here is that the cost does not move with the number of blogs; the
  # absolute number belongs to Rails.
  it "reads a roster of any size in the same number of queries" do
    sign_in
    create(:blog)
    get subscriptions_path
    one_blog = count_queries { get subscriptions_path }

    4.times { create(:blog) }

    expect(count_queries { get subscriptions_path }).to eq(one_blog)
  end

  it "counts the posts each blog has stored" do
    sign_in
    blog = create(:blog, title: "Query Plan Weekly")
    create_list(:blog_post, 2, blog: blog)

    get subscriptions_path

    expect(response.body).to include("2 posts")
  end

  # What the bookmarklet on the Settings page sends over: the page the reader
  # was standing on, which Blog::Subscription reads for the feed it announces.
  it "fills the form with an address handed over in the query" do
    sign_in

    get subscriptions_path(feed_url: "https://queryplanweekly.dev/")

    expect(response.body).to include("https://queryplanweekly.dev/")
  end

  # Reflected into a field the reader is looking at, so what arrives is held
  # to the format the column is held to rather than printed as it came.
  it "drops a query parameter that is not an address" do
    sign_in

    get subscriptions_path(feed_url: "javascript:alert(1)")

    expect(response.body).not_to include("javascript:alert(1)")
  end

  # The address is filled in, never followed. Following on a GET would put a
  # blog on the roster for any page that embedded the URL, and would be a
  # create outside the resourceful route that owns it.
  # Served so the feed would be taken if anything asked for it — without that
  # the example passes on WebMock refusing the fetch, and would go on passing
  # with a follow wired into this action.
  it "does not follow a blog handed over in the query" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document(rss_article("One")))

    get subscriptions_path(feed_url: "https://queryplanweekly.dev/feed")

    expect(Blog.count).to eq(0)
  end
end
