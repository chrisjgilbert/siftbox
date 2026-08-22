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

  # Two answers in turn, which is what following a home page takes: the page
  # first, then the feed it announced.
  def returning_each(*documents)
    answers = documents.dup

    ->(_blog) do
      document = answers.shift
      Blog::Fetch::Fetched.new(document: document, etag: "", last_modified: "")
    end
  end

  # What a feed set to publish excerpts carries: WordPress's default is 55
  # words, which reads through Newsletter::Prose at a little over three
  # hundred characters.
  def excerpt(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>#{"word " * 55}</description>
      </item>
    ITEM
  end

  def follow(feed_url, fetch)
    blog = Blog.new(feed_url: feed_url)

    [ Blog::Subscription.new(blog, fetch: fetch).submit, blog ]
  end

  it "follows a feed that carries writing" do
    followed, _blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One") + rss_article("Two"))))

    expect(followed).to be(true)
    expect(Blog.count).to eq(1)
  end

  # The first poll is the sample, not a second request: the reader is standing
  # there, and the document that was just read is the one to read from.
  it "stores the posts it sampled rather than fetching them again" do
    follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One") + rss_article("Two"))))

    expect(Blog::Post.count).to eq(2)
  end

  it "takes the blog's name from the feed it sampled" do
    _followed, blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One"))))

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
      returning(rss_document(rss_article("One") + rss_article("Two") + link("Three"))))

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

  # A blog followed by its feed address, then pasted again as its home page:
  # the hop rewrites feed_url after Blog was validated, so save! raised
  # RecordInvalid out of the model and the reader got a 500 where the same
  # duplicate pasted directly gets a polite message under the field.
  it "refuses a home page whose feed is already on the roster" do
    create(:blog, feed_url: "https://queryplanweekly.dev/feed")

    followed, blog = follow("https://queryplanweekly.dev", returning_each(
      home_page("https://queryplanweekly.dev/feed"), rss_document(rss_article("One"))
    ))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/already been taken/)
  end

  # The address the reader typed, not the one the app went looking for. The
  # form redisplays this, and "check the address points at the feed" is wrong
  # advice about a page they never saw.
  it "keeps the address the reader typed when a discovered feed is refused" do
    _followed, blog = follow("https://queryplanweekly.dev", returning_each(
      home_page("https://queryplanweekly.dev/feed"),
      rss_document(link("One") + link("Two"))
    ))

    expect(blog.feed_url).to eq("https://queryplanweekly.dev")
  end

  # A blog row that exists with nothing in it reads "Not checked yet" forever,
  # the reader is shown an error page, and a retry earns "already been taken".
  it "leaves no blog behind when the poll raises after the row is written" do
    allow(RemoteImagesJob).to receive(:perform_later).and_raise(ActiveRecord::StatementInvalid)

    suppress(ActiveRecord::StatementInvalid) do
      follow("https://queryplanweekly.dev/feed", returning(rss_document(rss_article("One"))))
    end

    expect(Blog.count).to eq(0)
  end

  # A blog that publishes two-line excerpts and a "read more" link is a blog.
  # WordPress ships that as the default for its Excerpt setting, and it
  # measures around 330 characters — below the editorial floor, and nowhere
  # near an aggregator's eight.
  it "follows a blog that publishes excerpts rather than whole articles" do
    followed, _blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(excerpt("One") + excerpt("Two"))))

    expect(followed).to be(true)
  end

  it "refuses a feed already on the roster" do
    create(:blog, feed_url: "https://queryplanweekly.dev/feed")

    followed, blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One"))))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to be_present
  end

  # Readers know their blogs by their home pages, not by their feed
  # addresses. Pasting the home page has to work, or the feature asks the
  # reader to go and find something most blogs do not show them.
  it "follows the feed a home page announces" do
    followed, blog = follow("https://queryplanweekly.dev", returning_each(
      home_page("https://queryplanweekly.dev/feed"),
      rss_document(rss_article("One"))
    ))

    expect(followed).to be(true)
    expect(blog.reload.feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  it "stores the posts from the feed a home page announced" do
    follow("https://queryplanweekly.dev", returning_each(
      home_page("https://queryplanweekly.dev/feed"), rss_document(rss_article("One"))
    ))

    expect(Blog::Post.count).to eq(1)
  end

  it "still refuses an aggregator reached through its home page" do
    followed, blog = follow("https://news.ycombinator.com", returning_each(
      home_page("https://news.ycombinator.com/rss"),
      rss_document(link("One") + link("Two"))
    ))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/link aggregator/)
  end

  # One hop and no more. A page announcing itself, or two pages announcing
  # each other, would otherwise walk until something else stopped it.
  it "does not follow a second page announced by the first" do
    asked = []
    fetch = lambda do |blog|
      asked << blog.feed_url
      Blog::Fetch::Fetched.new(
        document: home_page("https://queryplanweekly.dev/#{asked.length}"),
        etag: "", last_modified: ""
      )
    end

    follow("https://queryplanweekly.dev", fetch)

    expect(asked.length).to eq(2)
  end

  it "says a page announcing no feed is not a feed" do
    followed, blog = follow("https://queryplanweekly.dev",
      returning("<html><head><title>Query Plan Weekly</title></head><body></body></html>"))

    expect(followed).to be(false)
    expect(blog.errors[:feed_url]).to include(/not a feed/)
  end

  # A page whose feed link points back at itself — href="#" or href="" — was
  # fetched a second time to be told the same thing. One request, and the
  # answer is the one already in hand.
  it "does not fetch a page that announces itself" do
    asked = []
    fetch = lambda do |blog|
      asked << blog.feed_url
      Blog::Fetch::Fetched.new(document: home_page("#"), etag: "", last_modified: "")
    end

    follow("https://queryplanweekly.dev/", fetch)

    expect(asked).to eq([ "https://queryplanweekly.dev/" ])
  end
end
