require "rails_helper"

RSpec.describe Blog::Subscription do
  # The document the feed would have answered with, handed over rather than
  # served: what these examples are about is what this class does with a
  # feed, not how it is fetched.
  def returning(document)
    ->(blog) { Blog::Fetch::Fetched.new(document: document, etag: "", last_modified: "") }
  end

  def unreachable
    ->(_blog) { nil }
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

  # What an aggregator publishes, measured rather than imagined: the body of a
  # Hacker News item is the word "Comments" and nothing else, because its
  # description is a link back to its own thread.
  def link(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://news.ycombinator.com/item?id=#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>Comments</description>
      </item>
    ITEM
  end

  def follow(feed_url, fetch)
    blog = Blog.new(feed_url: feed_url)

    [ Blog::Subscription.new(blog, fetch: fetch).submit, blog ]
  end

  it "follows a feed that carries writing" do
    followed, _blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(article("One") + article("Two"))))

    expect(followed).to be(true)
    expect(Blog.count).to eq(1)
  end

  # The first poll is the sample, not a second request: the reader is standing
  # there, and the document that was just read is the one to read from.
  it "stores the posts it sampled rather than fetching them again" do
    follow("https://queryplanweekly.dev/feed",
      returning(rss_document(article("One") + article("Two"))))

    expect(Blog::Post.count).to eq(2)
  end

  it "takes the blog's name from the feed it sampled" do
    _followed, blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(article("One"))))

    expect(blog.reload.title).to eq("Query Plan Weekly")
  end

  it "refuses a feed whose items are all stubs" do
    followed, blog = follow("https://news.ycombinator.com/rss",
      returning(rss_document(link("One") + link("Two") + link("Three"))))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/link aggregator/)
  end

  it "keeps a refused feed off the roster" do
    follow("https://news.ycombinator.com/rss", returning(rss_document(link("One"))))

    expect(Blog.count).to eq(0)
  end

  # A majority rather than all of them, and the numbers are miles apart: the
  # aggregators measured for docs/blogs-rss.md have a median body of eight
  # characters, where 9 of 273 in-scope items came under four hundred.
  it "follows a blog that publishes the occasional stub" do
    followed, _blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(article("One") + article("Two") + link("Three"))))

    expect(followed).to be(true)
  end

  it "refuses a feed that could not be fetched" do
    followed, blog = follow("https://queryplanweekly.dev/feed", unreachable)

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/could not be read/)
  end

  it "refuses a document that is not a feed" do
    followed, blog = follow("https://queryplanweekly.dev/feed",
      returning("<html><body><p>Not a feed.</p></body></html>"))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/not a feed/)
  end

  it "refuses a feed carrying no items at all" do
    followed, blog = follow("https://queryplanweekly.dev/feed", returning(rss_document))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/nothing/)
  end

  # Blog's own validations still hold, and the fetch is not spent finding out.
  it "refuses an address that is not a fetchable one, without asking for it" do
    asked = []
    follow("file:///etc/passwd", ->(blog) { asked << blog })

    expect(asked).to be_empty
  end

  it "refuses a feed already on the roster" do
    create(:blog, feed_url: "https://queryplanweekly.dev/feed")

    followed, blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(article("One"))))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to be_present
  end
end
