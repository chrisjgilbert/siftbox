require "rails_helper"

# The roster, read and written the way a reader does it: paste a feed, see it
# arrive, take one off again. It sits on the Subscriptions page because that
# is where the reader already goes to see what reaches them and what does not.
RSpec.describe "The blogs on the Subscriptions page" do
  # The one thing a system spec cannot let out of the process. Stopped at the
  # seam Blog::Subscription takes for its sample, so everything on this side
  # of it — the form, the refusal, the roster — is the real thing.
  def feed_answering(*documents)
    answers = documents.dup
    allow(Blog::Subscription).to receive(:new).and_wrap_original do |original, blog, **|
      original.call(blog, fetch: lambda do |_blog|
        Blog::Fetch::Fetched.new(document: answers.shift, etag: "", last_modified: "")
      end)
    end
  end

  # A blog's home page, announcing where its feed is.
  def home_page(feed_url)
    <<~HTML
      <!DOCTYPE html>
      <html><head><title>Query Plan Weekly</title>
      <link rel="alternate" type="application/rss+xml" href="#{feed_url}"></head>
      <body><p>Notes on databases.</p></body></html>
    HTML
  end

  def article(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>#{"word " * 200}</description>
      </item>
    ITEM
  end

  def aggregated(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://news.ycombinator.com/item?id=1</link>
        <guid>hn-#{title.parameterize}</guid>
        <description>Comments</description>
      </item>
    ITEM
  end

  def follow(feed_url)
    fill_in "Feed address", with: feed_url
    click_button "Follow"
  end

  it "says the roster is empty before anything is on it" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Blogs").and have_text("No blogs yet")
  end

  it "puts a followed blog on the roster with what it read" do
    feed_answering(rss_document(article("One") + article("Two")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://queryplanweekly.dev/feed")

    expect(page).to have_text("Query Plan Weekly").and have_text("2 posts")
  end

  # The whole reason the check is made while the reader is standing there:
  # refusing later, silently, tells them nothing.
  it "refuses a link aggregator and says why" do
    feed_answering(rss_document(aggregated("One") + aggregated("Two")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://news.ycombinator.com/rss")

    expect(page).to have_text("looks like a link aggregator")
  end

  it "keeps the address in the form after refusing it" do
    feed_answering(rss_document(aggregated("One")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://news.ycombinator.com/rss")

    expect(page).to have_field("Feed address", with: "https://news.ycombinator.com/rss")
  end

  it "takes a blog off the roster" do
    create(:blog, title: "Query Plan Weekly")
    sign_in_through_the_form

    visit subscriptions_path
    click_button "Remove"

    expect(page).to have_text("No blogs yet")
  end

  it "says how long a blog has not been answering" do
    create(:blog, title: "Query Plan Weekly", polled_at: 1.minute.ago,
      failing_since: 3.days.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Not answering for 3 days")
  end

  it "says a blog has not been checked yet" do
    create(:blog, title: "Query Plan Weekly", polled_at: nil)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Not checked yet")
  end

  # Readers know their blogs by their home pages. Most sites never show a feed
  # address at all, so pasting one is the case, not the exception.
  it "follows the feed a pasted home page announces" do
    feed_answering(home_page("/feed"), rss_document(article("One")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://queryplanweekly.dev")

    expect(page).to have_text("https://queryplanweekly.dev/feed").and have_text("1 post")
  end
end
