require "rails_helper"

RSpec.describe Blog::Subscription do
  include ActiveJob::TestHelper

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
  # What an aggregator publishes once its template has wrapped the word in an
  # anchor: markup enough to clear any floor measured on the body.
  def wrapped_link(title)
    anchor = %(&lt;a href="https://news.ycombinator.com/item?id=4083356782" ) +
      %(rel="nofollow noopener noreferrer" target="_blank" class="comments-link" ) +
      %(data-item="4083356782"&gt;Comments&lt;/a&gt;)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://news.ycombinator.com/item?id=1</link>
        <guid>hn-#{title.parameterize}</guid>
        <description>#{anchor}</description>
      </item>
    ITEM
  end

  # Longer than "Comments" and still a pointer rather than writing.
  def pointer(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>Read the rest here.</description>
      </item>
    ITEM
  end

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

  # The reader waits for the decision, not for the archive. Storing a real
  # blog's back catalogue took twenty seconds inside the request, on a thread
  # the whole app shares three of.
  it "asks for the blog to be polled rather than storing it inline" do
    _followed, blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One") + rss_article("Two"))))

    expect(Blog::PollJob).to have_been_enqueued.with(blog)
    expect(Blog::Post.count).to eq(0)
  end

  it "asks for nothing when the feed was refused" do
    follow("https://news.ycombinator.com/rss",
      returning(rss_document(link("One") + link("Two"))))

    expect(Blog::PollJob).not_to have_been_enqueued
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

  # A feed's character shows in its first items, and reading a back catalogue
  # of 128 to decide told us nothing the first twenty did — measured at ten
  # seconds of the twenty-one a real blog's first subscription took.
  #
  # Asserted on the decision rather than on how many bodies were read: an
  # example counting calls to Newsletter::Body.prose passes for any mutation
  # that keeps calling it, which is how a version measuring markup instead of
  # prose stayed green. This holds both ends — a sample too large reaches the
  # articles and admits the feed, a sample read from the wrong end does too.
  it "judges a feed on its newest items rather than on its back catalogue" do
    stubs = (1..Blog::Subscription::SAMPLE).map { |number| link("Stub #{number}") }.join
    articles = (1..Blog::Subscription::SAMPLE).map { |number| rss_article("Post #{number}") }.join

    followed, _blog = follow("https://news.ycombinator.com/rss",
      returning(rss_document(stubs + articles)))

    expect(followed).to be(false)
  end

  # An aggregator that wraps its one word in an anchor: 238 characters of
  # markup around 8 of prose. Measured against a real Hacker News item's
  # shape, and the reason the floor is read off the prose rather than off the
  # body — a rule the sampling example above cannot hold on its own.
  it "refuses an aggregator whose links carry more markup than writing" do
    followed, _blog = follow("https://news.ycombinator.com/rss",
      returning(rss_document(wrapped_link("One") + wrapped_link("Two"))))

    expect(followed).to be(false)
  end

  # The share, from below as well as above. Every aggregator elsewhere in this
  # file has no readable items at all, so a rule admitting one item in ten
  # would still refuse them.
  it "refuses a feed where two items in five carry writing" do
    items = rss_article("One") + rss_article("Two") +
      (3..5).map { |number| link("Stub #{number}") }.join

    followed, _blog = follow("https://queryplanweekly.dev/feed", returning(rss_document(items)))

    expect(followed).to be(false)
  end

  it "follows a feed where three items in five carry writing" do
    items = (1..3).map { |number| rss_article("Article #{number}") }.join +
      link("Stub four") + link("Stub five")

    followed, _blog = follow("https://queryplanweekly.dev/feed", returning(rss_document(items)))

    expect(followed).to be(true)
  end

  # At least half is the rule, so half is enough.
  it "follows a feed exactly half of which is writing" do
    followed, _blog = follow("https://queryplanweekly.dev/feed",
      returning(rss_document(rss_article("One") + link("Two"))))

    expect(followed).to be(true)
  end

  # The stub floor from below. The only stub elsewhere in this file is the
  # literal word "Comments", so any floor above eight refused it.
  it "refuses a feed of one-line pointers" do
    followed, _blog = follow("https://news.ycombinator.com/rss",
      returning(rss_document(pointer("One") + pointer("Two"))))

    expect(followed).to be(false)
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

  it "asks for the feed a home page announced to be polled" do
    _followed, blog = follow("https://queryplanweekly.dev", returning_each(
      home_page("https://queryplanweekly.dev/feed"), rss_document(rss_article("One"))
    ))

    expect(Blog::PollJob).to have_been_enqueued.with(blog)
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

  # "Once, and only from a document that was not a feed." The once was held;
  # the only-from-a-non-feed was not, so a feed that also carries an alternate
  # link earned a second fetch and was followed at an address the reader never
  # typed.
  it "does not chase an alternate link out of a document that is a feed" do
    asked = []
    fetch = lambda do |blog|
      asked << blog.feed_url
      document = rss_document(rss_article("One")).sub("<channel>",
        %(<channel><link rel="alternate" type="application/rss+xml" href="/other"/>))
      Blog::Fetch::Fetched.new(document: document, etag: "", last_modified: "")
    end

    follow("https://queryplanweekly.dev/feed", fetch)

    expect(asked).to eq([ "https://queryplanweekly.dev/feed" ])
  end
end
