require "rails_helper"

RSpec.describe Blog::Feed do
  # An RSS 2.0 channel carrying whatever items the example needs. The channel
  # furniture is required by the format and says nothing the parser is being
  # asked about, so it lives here rather than in every example.
  def rss_document(items)
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel>
          <title>Query Plan Weekly</title>
          <link>https://queryplanweekly.dev</link>
          <description>Notes on databases</description>
      #{items}
        </channel>
      </rss>
    XML
  end

  # The same blog, published as Atom. Every field the parser wants is spelled
  # differently here — entry for item, link as an attribute, content and
  # published as elements with their own .content — which is the whole of what
  # the adapter below is for.
  def atom_document
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Query Plan Weekly</title>
        <id>https://queryplanweekly.dev/</id>
        <updated>2026-08-21T06:30:00Z</updated>
        <author><name>Query Plan Weekly</name></author>
        <link href="https://queryplanweekly.dev/"/>
        <entry>
          <title>Why your index is not being used</title>
          <id>https://queryplanweekly.dev/unused-index</id>
          <link href="https://queryplanweekly.dev/unused-index"/>
          <published>2026-08-21T06:30:00Z</published>
          <updated>2026-08-21T06:30:00Z</updated>
          <content type="html">&lt;p&gt;The planner has its reasons.&lt;/p&gt;</content>
        </entry>
      </feed>
    XML
  end

  # A billion-laughs bomb: six levels of entity, each ten copies of the last,
  # so &f; expands to ten million characters from a document of a few hundred
  # bytes. Feed XML is written by strangers, so this is a document this app
  # can be sent rather than one it would ever produce.
  def entity_bomb
    definitions = %w[a b c d e f].each_cons(2).map do |previous, this|
      %(<!ENTITY #{this} "#{"&#{previous};" * 10}">)
    end

    <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE rss [
      <!ENTITY a "aaaaaaaaaa">
      #{definitions.join("\n")}
      ]>
      <rss version="2.0"><channel><title>x</title><link>https://x.dev</link>
      <description>&f;</description></channel></rss>
    XML
  end

  it "reads one post per item in an RSS document" do
    document = rss_document(<<~ITEMS)
      <item><title>Why your index is not being used</title></item>
      <item><title>Counting rows is harder than it looks</title></item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.map(&:title))
      .to eq([ "Why your index is not being used", "Counting rows is harder than it looks" ])
  end

  it "reads a post's address from its link" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <link>https://queryplanweekly.dev/unused-index</link>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.url).to eq("https://queryplanweekly.dev/unused-index")
  end

  it "reads a post's body from its description" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <description>&lt;p&gt;The planner has its reasons.&lt;/p&gt;</description>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html).to eq("<p>The planner has its reasons.</p>")
  end

  # The common shape for a blog that publishes full text: description carries
  # a summary for readers who only get that far, content:encoded the article.
  it "prefers a post's encoded content to its description" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <description>The planner has its reasons.</description>
        <content:encoded>&lt;p&gt;The planner has its reasons, and here they are in full.&lt;/p&gt;</content:encoded>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html)
      .to eq("<p>The planner has its reasons, and here they are in full.</p>")
  end

  # RSS dates are RFC-822 and Atom's are ISO-8601. Reading both is most of why
  # this is the rss gem's job rather than a few Nokogiri selectors.
  it "reads a post's publication date as a time" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <pubDate>Thu, 21 Aug 2026 06:30:00 +0000</pubDate>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.published_at).to eq(Time.utc(2026, 8, 21, 6, 30))
  end

  it "reads the same fields out of an Atom document" do
    feed = Blog::Feed.new(atom_document)

    expect(feed.posts.first).to eq(
      Blog::Feed::Item.new(
        title: "Why your index is not being used",
        url: "https://queryplanweekly.dev/unused-index",
        body_html: "<p>The planner has its reasons.</p>",
        published_at: Time.utc(2026, 8, 21, 6, 30)
      )
    )
  end

  it "refuses a document whose entities expand without bound" do
    feed = Blog::Feed.new(entity_bomb)

    expect { feed.posts }.to raise_error(Blog::Feed::Malformed)
  end

  # The other half of the same worry. An external entity is a request for a
  # file on this server, written into a document by whoever publishes the
  # feed — so what matters is that the reference survives as text rather than
  # being resolved into whatever it names.
  it "does not resolve an external entity" do
    document = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE rss [ <!ENTITY secret SYSTEM "file:///etc/hostname"> ]>
      <rss version="2.0"><channel>
      <title>Query Plan Weekly</title><link>https://queryplanweekly.dev</link>
      <description>Notes on databases</description>
      <item><title>Why your index is not being used</title>
      <description>&secret;</description></item>
      </channel></rss>
    XML

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html).to eq("&secret;")
  end
end
