require "rails_helper"

RSpec.describe Blog::Feed do
  # An RSS 2.0 channel carrying whatever items the example needs. The channel
  # furniture is required by the format and says nothing the parser is being
  # asked about, so it lives here rather than in every example.
  def rss_document(items)
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/">
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
  def atom_document(entry)
    <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Query Plan Weekly</title>
        <id>https://queryplanweekly.dev/</id>
        <updated>2026-08-21T06:30:00Z</updated>
        <author><name>Query Plan Weekly</name></author>
        <link href="https://queryplanweekly.dev/"/>
      #{entry}
      </feed>
    XML
  end

  # The entry the Atom example reads, carrying every field the parser wants.
  def atom_entry
    <<~XML
      <entry>
        <title>Why your index is not being used</title>
        <id>https://queryplanweekly.dev/unused-index</id>
        <link href="https://queryplanweekly.dev/unused-index"/>
        <published>2026-08-21T06:30:00Z</published>
        <updated>2026-08-21T06:30:00Z</updated>
        <content type="html">&lt;p&gt;The planner has its reasons.&lt;/p&gt;</content>
      </entry>
    XML
  end

  # A billion-laughs bomb: six levels of entity, each ten copies of the last,
  # so &f; unpacks to a million characters from a few hundred bytes. Feed XML
  # is written by strangers, so this is a document this app can be sent rather
  # than one it would ever produce.
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
    feed = Blog::Feed.new(atom_document(atom_entry))

    expect(feed.posts.first).to eq(
      Blog::Feed::Item.new(
        title: "Why your index is not being used",
        url: "https://queryplanweekly.dev/unused-index",
        body_html: "<p>The planner has its reasons.</p>",
        published_at: Time.utc(2026, 8, 21, 6, 30),
        identity: "https://queryplanweekly.dev/unused-index"
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

  # Publishing tools emit an empty content:encoded for a post that has none,
  # and an empty string is not the same as an absent field: it wins the
  # preference above on presence alone and hands the editor nothing at all.
  it "falls back to the description when the encoded content is empty" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <description>The planner has its reasons.</description>
        <content:encoded></content:encoded>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html).to eq("The planner has its reasons.")
  end

  # The same hole on the Atom side, and it is the reason the emptiness has to
  # be judged after the element is unwrapped: an empty <content> is a perfectly
  # present object holding an empty string.
  it "falls back to the summary when an Atom entry's content is empty" do
    document = atom_document(<<~ENTRY)
      <entry>
        <title>Why your index is not being used</title>
        <id>https://queryplanweekly.dev/unused-index</id>
        <updated>2026-08-21T06:30:00Z</updated>
        <summary>The planner has its reasons.</summary>
        <content type="html"></content>
      </entry>
    ENTRY

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html).to eq("The planner has its reasons.")
  end

  # The shape that escapes a rescue on the parser's own errors: this is
  # well-formed XML, so nothing raises — the parser simply does not recognise
  # it and answers nothing at all. A blog that moves and leaves an SPA
  # fallback, a parked domain, or a WAF interstitial serves exactly this,
  # with a 200.
  it "refuses a document that is well formed but is not a feed" do
    feed = Blog::Feed.new(<<~XML)
      <!DOCTYPE html>
      <html><head><title>Blog moved</title></head>
      <body><p>We are on Substack now.</p></body></html>
    XML

    expect { feed.posts }.to raise_error(Blog::Feed::Malformed)
  end

  # RSS 2.0 says pubDate is RFC-822, and static-site generators emit ISO-8601
  # there all the time. Under the parser's strict default one such field
  # discards every post in the document, so a blog whose generator is a little
  # loose is unreadable forever rather than for one post.
  it "reads a feed whose dates are in the wrong format for its own spec" do
    document = rss_document(<<~ITEMS)
      <item><title>Loose</title><pubDate>2026-08-21T06:30:00Z</pubDate></item>
      <item><title>Correct</title><pubDate>Wed, 20 Aug 2026 09:00:00 +0000</pubDate></item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.map(&:title)).to eq([ "Loose", "Correct" ])
  end

  # Bytes tagged as the wrong encoding raise from inside the parser as an
  # ArgumentError, which is not one of the parser's own errors and so walks
  # straight past a rescue written for those. The fetch is what should be
  # handing this class UTF-8, the way Newsletter::InboundMessage does for
  # mail — but a class that promises one error has to keep the promise even
  # when its caller is wrong.
  it "refuses a document whose bytes are tagged as the wrong encoding" do
    document = rss_document(<<~ITEMS).dup.force_encoding(Encoding::US_ASCII)
      <item><title>Why your index is not being used — a note</title></item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect { feed.posts }.to raise_error(Blog::Feed::Malformed)
  end

  # Which element carries the article cannot be told from its name. The
  # measurement behind docs/blogs-rss.md found Dan Luu publishing full
  # articles in <summary> — 128 items, median 11,997 characters — so a fixed
  # preference for <content> is a guess, and when it guesses wrong it hands
  # the editor a teaser and the edition reports a full post as a stub.
  it "takes the fuller body when a feed puts the article in the summary" do
    document = atom_document(<<~ENTRY)
      <entry>
        <title>Why your index is not being used</title>
        <id>https://queryplanweekly.dev/unused-index</id>
        <updated>2026-08-21T06:30:00Z</updated>
        <summary>The planner has its reasons, and here they are at length.</summary>
        <content type="html">Read the rest on the site.</content>
      </entry>
    ENTRY

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html)
      .to eq("The planner has its reasons, and here they are at length.")
  end

  # Dublin Core's date, which RSS 1.0 has instead of pubDate rather than as
  # well as it — so a feed in that format has no date at all without this, and
  # published_at is what the archive sorts by and what the first-poll guard
  # reads to decide whether a post is new.
  it "reads a post's date from dc:date when there is no pubDate" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <dc:date>2026-08-21T06:30:00+00:00</dc:date>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.published_at).to eq(Time.utc(2026, 8, 21, 6, 30))
  end

  # The order Blogger and WordPress emit. An Atom entry may carry several
  # links and only the one with no rel, or rel="alternate", is the post
  # itself; the others are the comment feed and the editing endpoint. Taking
  # whichever came first sends the reader to a comments document, and — since
  # the address is also what identifies a post when it has no id — files it
  # under the wrong key.
  it "takes the alternate link when an Atom entry carries several" do
    document = atom_document(<<~ENTRY)
      <entry>
        <title>t</title><id>i</id><updated>2026-08-21T06:30:00Z</updated>
        <link rel="replies" href="https://queryplanweekly.dev/x/comments"/>
        <link rel="edit" href="https://queryplanweekly.dev/api/1"/>
        <link rel="alternate" href="https://queryplanweekly.dev/x"/>
        <summary>s</summary>
      </entry>
    ENTRY

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.url).to eq("https://queryplanweekly.dev/x")
  end

  # Atom marks a plain-text body with type="text". Stored as it stands it
  # lands in an HTML column, and the first bare < swallows the rest of the
  # post — either as an unterminated tag in the browser or under the
  # sanitiser's pruning.
  it "escapes an Atom body that is marked as plain text" do
    document = atom_document(<<~ENTRY)
      <entry>
        <title>t</title><id>i</id><updated>2026-08-21T06:30:00Z</updated>
        <content type="text">if a &lt; b then print &quot;hi&quot;</content>
      </entry>
    ENTRY

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.body_html).to eq("if a &lt; b then print &quot;hi&quot;")
  end

  # What "seen this one before" is decided on. RSS calls it guid, Atom calls
  # it id, and both are the publisher's own name for the post rather than
  # anything derived from it — which is what makes polling the same feed
  # twice store nothing the second time.
  it "reads a post's identity from its guid" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <guid isPermaLink="false">tag:queryplanweekly.dev,2026:1481</guid>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.identity).to eq("tag:queryplanweekly.dev,2026:1481")
  end

  it "reads a post's identity from an Atom id" do
    feed = Blog::Feed.new(atom_document(atom_entry))

    expect(feed.posts.first.identity)
      .to eq("https://queryplanweekly.dev/unused-index")
  end

  # RSS 2.0 lets an item carry its address in the guid instead of a link,
  # when the guid is marked as a permalink. Without this such a post has no
  # address at all — nothing for the archive to link to, and nothing for the
  # edition to cite.
  it "takes the address from a permalink guid when there is no link" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <guid isPermaLink="true">https://queryplanweekly.dev/unused-index</guid>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.url).to eq("https://queryplanweekly.dev/unused-index")
  end

  # Atom requires `updated` and makes `published` optional, so this is the
  # shape a feed that sets only the required date arrives in. Without the
  # fallback every post from such a blog is undated.
  it "dates an Atom entry from updated when it has no published" do
    document = atom_document(<<~ENTRY)
      <entry>
        <title>t</title><id>i</id>
        <updated>2026-08-21T06:30:00Z</updated>
        <summary>s</summary>
      </entry>
    ENTRY

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.published_at).to eq(Time.utc(2026, 8, 21, 6, 30))
  end

  # A legal item carrying nothing but a title. Written down because these are
  # the values Blog::Poll has to decide about — an undated post cannot be
  # placed in a window, and an addressless one cannot be linked to.
  it "reads an item that carries nothing but a title" do
    document = rss_document("<item><title>Bare</title></item>")

    feed = Blog::Feed.new(document)

    expect(feed.posts.first).to eq(
      Blog::Feed::Item.new(
        title: "Bare", url: "", body_html: "", published_at: nil, identity: ""
      )
    )
  end

  # RSS 2.0 makes isPermaLink default to true, so a bare guid is a permalink
  # unless the feed says otherwise — and a bare guid is how most feeds that
  # use one spell it. The parser reports the missing attribute as nil rather
  # than as the default, so nil has to be read as the yes it means.
  it "takes the address from a guid that does not say it is a permalink" do
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <guid>https://queryplanweekly.dev/unused-index</guid>
      </item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.first.url).to eq("https://queryplanweekly.dev/unused-index")
  end
end
