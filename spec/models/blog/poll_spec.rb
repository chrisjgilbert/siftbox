require "rails_helper"

RSpec.describe Blog::Poll do
  include ActiveJob::TestHelper

  # The fetch is injected rather than performed, so every example here is a
  # string. rss_document wraps the items in the channel furniture the format
  # requires; see spec/support/feed_documents.rb.
  def one_post
    rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <link>https://queryplanweekly.dev/unused-index</link>
        <guid>https://queryplanweekly.dev/unused-index</guid>
        <pubDate>Thu, 21 Aug 2026 06:30:00 +0000</pubDate>
        <description>The planner has its reasons.</description>
      </item>
    ITEMS
  end

  # A post the feed never named: no guid, and no link either. Plenty of
  # hand-rolled feeds publish like this.
  def unnamed_post(title)
    <<~ITEMS
      <item>
        <title>#{title}</title>
        <description>Something happened.</description>
      </item>
    ITEMS
  end

  def dated_post(title, published)
    <<~ITEMS
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <pubDate>#{published.rfc822}</pubDate>
        <description>Something happened.</description>
      </item>
    ITEMS
  end

  def returning(document)
    ->(_blog) { Blog::Fetch::Fetched.new(document: document, etag: "", last_modified: "") }
  end

  def unchanged
    ->(_blog) { Blog::Fetch::UNCHANGED }
  end

  def failing
    ->(_blog) { nil }
  end

  it "stores a post the blog has not published before" do
    blog = create(:blog)

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.posts.pluck(:title)).to eq([ "Why your index is not being used" ])
  end

  # The point of the whole exercise. A feed is polled hourly and mostly has
  # not changed, so storing nothing is the ordinary outcome — and a post
  # stored twice would be cited twice and read twice.
  it "stores nothing the second time it reads the same feed" do
    blog = create(:blog)
    poll = Blog::Poll.new(blog, fetch: returning(one_post))
    poll.save

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.posts.count).to eq(1)
  end

  # An identity of "" is not an identity, and treating it as one means the
  # first unnamed post a blog publishes is the last one it can ever publish:
  # every later post matches the stored empty string and is skipped as
  # already seen.
  it "stores a second post the feed never named" do
    blog = create(:blog)
    first = rss_document(unnamed_post("Weeknotes for August"))
    Blog::Poll.new(blog, fetch: returning(first)).save

    both = rss_document(unnamed_post("Weeknotes for August") + unnamed_post("A note on locks"))
    Blog::Poll.new(blog, fetch: returning(both)).save

    expect(blog.posts.pluck(:title))
      .to contain_exactly("Weeknotes for August", "A note on locks")
  end

  # A feed carries a back catalogue, not just what is new. On the day a blog
  # is added its whole archive arrives at once, and received_at is what an
  # edition window runs on — so dating the old ones now would put years of
  # writing into tomorrow morning's edition.
  it "keeps a back catalogue out of the window on a blog's first poll" do
    blog = create(:blog, polled_at: nil)
    document = rss_document(
      dated_post("An old post", 2.years.ago) + dated_post("A new post", 1.hour.ago)
    )

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.where(received_at: 1.week.ago..).pluck(:title))
      .to eq([ "A new post" ])
  end

  # Everything is stored, though. The archive is better for having the back
  # catalogue in it, and the reader who just subscribed may well want to
  # browse it — it is only the edition window that should not see it.
  it "still stores the back catalogue it kept out of the window" do
    blog = create(:blog, polled_at: nil)
    document = rss_document(
      dated_post("An old post", 2.years.ago) + dated_post("A new post", 1.hour.ago)
    )

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.count).to eq(2)
  end

  it "records when it last read the feed" do
    blog = create(:blog, polled_at: nil)

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.reload.polled_at).to be_present
  end

  # The guard belongs to the first poll alone. A blog that has been read
  # before and then publishes something back-dated — a piece written weeks
  # ago and released today — is new to this app, and the edition should
  # cover it rather than file it in the archive unread.
  it "treats a back-dated post as new once the blog has been polled before" do
    blog = create(:blog, polled_at: nil)
    Blog::Poll.new(blog, fetch: returning(one_post)).save

    later = rss_document(dated_post("Written weeks ago", 3.weeks.ago))
    Blog::Poll.new(blog.reload, fetch: returning(later)).save

    expect(blog.posts.where(received_at: 1.week.ago..).pluck(:title))
      .to include("Written weeks ago")
  end

  # A feed that lists the same post twice — a generator bug, or a post edited
  # into a second entry. The index refuses the duplicate, which rolls the
  # transaction back, which un-stamps polled_at: the blog then fails the same
  # way on every hourly poll from then on, and never stores anything again.
  it "stores one post when a feed lists the same one twice" do
    blog = create(:blog)
    twice = rss_document(unnamed_post("Weeknotes") + unnamed_post("Weeknotes"))

    Blog::Poll.new(blog, fetch: returning(twice)).save

    expect(blog.posts.count).to eq(1)
  end

  # An undated post on a first poll cannot be shown to be new, and a feed
  # with no dates at all is an ordinary shape — RSS 1.0 without dc:date, and
  # plenty of hand-rolled feeds. Read as new they take the whole archive into
  # the window, which is the failure the guard exists to prevent, so the
  # honest reading of "no date" on a first poll is "not demonstrably new".
  it "keeps undated posts out of the window on a first poll" do
    blog = create(:blog, polled_at: nil)
    document = rss_document(
      unnamed_post("One") + unnamed_post("Two") + unnamed_post("Three")
    )

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.where(received_at: 6.days.ago..).count).to eq(0)
  end

  it "stores nothing when the feed says it has not changed" do
    blog = create(:blog)
    Blog::Poll.new(blog, fetch: returning(one_post)).save

    Blog::Poll.new(blog.reload, fetch: unchanged).save

    expect(blog.posts.count).to eq(1)
  end

  # What the next conditional request is built from. Without writing these
  # back the poll asks unconditionally every hour and the publisher serves the
  # whole feed every time.
  it "records the validators the feed sent for next time" do
    blog = create(:blog)
    fetch = ->(_blog) do
      Blog::Fetch::Fetched.new(document: one_post, etag: "\"abc\"", last_modified: "Wed")
    end

    Blog::Poll.new(blog, fetch: fetch).save

    expect(blog.reload.etag).to eq("\"abc\"")
  end

  # A feed that has stopped answering is the failure the reader would
  # otherwise never find out about: no posts, no error, and a blog that looks
  # exactly like one that has stopped publishing.
  it "marks a blog as failing when the fetch comes back with nothing" do
    blog = create(:blog, failing_since: nil)

    Blog::Poll.new(blog, fetch: failing).save

    expect(blog.reload.failing_since).to be_present
  end

  it "keeps the first failure's time when it fails again" do
    blog = create(:blog, failing_since: 3.days.ago)

    Blog::Poll.new(blog, fetch: failing).save

    expect(blog.reload.failing_since).to be < 2.days.ago
  end

  it "stops marking a blog as failing once it answers again" do
    blog = create(:blog, failing_since: 3.days.ago)

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.reload.failing_since).to be_nil
  end

  # The guard belongs to the first poll that actually stored anything, not to
  # the first attempt. A blog whose first fetch failed has been polled — so
  # keying on polled_at would drop the guard and let the back catalogue it has
  # never yet read pour into the next edition the moment it recovers.
  it "still guards the back catalogue after a first poll that failed" do
    blog = create(:blog, polled_at: nil)
    Blog::Poll.new(blog, fetch: failing).save

    document = rss_document(dated_post("An old post", 2.years.ago))
    Blog::Poll.new(blog.reload, fetch: returning(document)).save

    expect(blog.posts.where(received_at: 1.week.ago..).count).to eq(0)
  end

  # The archive row shows a line of the post and a thumbnail, and both are
  # read off the body the same way a newsletter's are — by the pipeline that
  # already exists and already knows nothing about mail.
  it "reads a snippet off the post's body" do
    blog = create(:blog)
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <guid>unused-index</guid>
        <description>&lt;p&gt;The planner has its reasons.&lt;/p&gt;</description>
      </item>
    ITEMS

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.first.snippet).to eq("The planner has its reasons.")
  end

  it "reads a lead image off the post's body" do
    blog = create(:blog)
    document = rss_document(<<~ITEMS)
      <item>
        <title>Why your index is not being used</title>
        <guid>unused-index</guid>
        <description>&lt;img src="https://queryplanweekly.dev/plan.png"&gt;&lt;p&gt;Text.&lt;/p&gt;</description>
      </item>
    ITEMS

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.first.lead_image_url).to eq("https://queryplanweekly.dev/plan.png")
  end

  # A 304 says "what you have is current", so the validators that earned it
  # are still the right ones to send next time. Clearing them makes the next
  # poll unconditional and the publisher serves the whole feed again — which
  # undoes the only reason for sending them.
  it "keeps the validators when the feed says it has not changed" do
    blog = create(:blog, etag: "\"abc\"", last_modified_header: "Wed")

    Blog::Poll.new(blog, fetch: unchanged).save

    expect(blog.reload.etag).to eq("\"abc\"")
  end

  # A blog serving something that is not a feed has stopped answering as far
  # as the reader cares, and recording that as a success leaves it looking
  # healthy forever while storing nothing.
  it "marks a blog as failing when its feed cannot be read" do
    blog = create(:blog, failing_since: nil)

    Blog::Poll.new(blog, fetch: returning("<html><body>gone</body></html>")).save

    expect(blog.reload.failing_since).to be_present
  end

  it "keeps no validators from a feed it could not read" do
    blog = create(:blog)

    fetch = ->(_blog) do
      Blog::Fetch::Fetched.new(document: "<html/>", etag: "\"abc\"", last_modified: "")
    end
    Blog::Poll.new(blog, fetch: fetch).save

    expect(blog.reload.etag).to eq("")
  end

  # A stalled host holds its connection for up to Download::MAX_DURATION.
  # Holding a database transaction open across that, once per blog, is what
  # RemoteImages documents itself as avoiding.
  it "does not hold a transaction open across the fetch" do
    blog = create(:blog)
    # The example itself runs inside a transaction, so depth rather than
    # openness is what says whether the poll opened one of its own.
    outside = ActiveRecord::Base.connection.open_transactions
    depth_during_fetch = nil
    fetch = ->(_blog) do
      depth_during_fetch = ActiveRecord::Base.connection.open_transactions
      Blog::Fetch::UNCHANGED
    end

    Blog::Poll.new(blog, fetch: fetch).save

    expect(depth_during_fetch).to eq(outside)
  end

  # Otherwise every row of the archive prints the feed's address where the
  # blog's name should be.
  it "takes the blog's name from the feed" do
    blog = create(:blog, title: "")

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.reload.title).to eq("Query Plan Weekly")
  end

  it "takes the blog's address from the feed" do
    blog = create(:blog, site_url: "")

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(blog.reload.site_url).to eq("https://queryplanweekly.dev")
  end

  # Off the poll rather than inside it, for the reason mail does the same: a
  # slow image host would otherwise hold the poll open, and the rest of the
  # roster behind it.
  it "asks for the images each stored post hotlinks" do
    blog = create(:blog)

    Blog::Poll.new(blog, fetch: returning(one_post)).save

    expect(RemoteImagesJob).to have_been_enqueued.with(blog.posts.sole)
  end

  it "asks for nothing when the poll stored no posts" do
    blog = create(:blog)
    Blog::Poll.new(blog, fetch: returning(one_post)).save

    Blog::Poll.new(blog.reload, fetch: returning(one_post)).save

    expect(RemoteImagesJob).to have_been_enqueued.exactly(:once)
  end

  # A guid of nothing but NUL bytes normalises to "" on the way into the
  # column, and #known reads through a partial index that excludes those — so
  # the post is invisible to the next poll and stored again, every hour,
  # forever. The key has to be computed the way the column stores it.
  it "stores a post whose guid was nothing but null bytes only once" do
    blog = create(:blog)
    document = rss_document(<<~ITEM)
      <item>
        <title>Why your index is not being used</title>
        <link>https://queryplanweekly.dev/unused-index</link>
        <guid>#{0.chr}</guid>
      </item>
    ITEM
    Blog::Poll.new(blog, fetch: returning(document)).save

    Blog::Poll.new(blog.reload, fetch: returning(document)).save

    expect(blog.posts.count).to eq(1)
  end

  # The fallback the empty key has to reach. Nothing is left to identify the
  # post by but its address, and that is what the chain is for.
  it "identifies such a post by its address instead" do
    blog = create(:blog)
    document = rss_document(<<~ITEM)
      <item>
        <title>Why your index is not being used</title>
        <link>https://queryplanweekly.dev/unused-index</link>
        <guid>#{0.chr}</guid>
      </item>
    ITEM

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.sole.guid).to eq("https://queryplanweekly.dev/unused-index")
  end

  # FIRST_POLL_WINDOW.ago is evaluated when the poll runs and the archive's
  # own horizon is evaluated when the page renders, which is always later — so
  # a post stamped exactly on the boundary is forever a hair too old to list.
  # Stored and reachable from nowhere, against the constant's own claim that
  # what an edition may cover on day one is what the archive is showing.
  it "keeps an undated first-poll post inside the archive's own horizon" do
    blog = create(:blog, polled_at: nil)

    Blog::Poll.new(blog, fetch: returning(rss_document(unnamed_post("One")))).save

    expect(blog.posts.sole.received_at).to be > Newsletter::Age::WINDOW.ago
  end

  # The memoisation, asserted for what it is rather than caught sideways. The
  # posts are created one at a time, so asking the database again after the
  # first would answer no for every post after it — and a blog whose whole
  # back catalogue arrives on one poll would have all but its first item
  # dated today and pulled into the next morning's edition.
  it "dates every post of a back catalogue by the same first-poll rule" do
    blog = create(:blog, polled_at: nil)
    document = rss_document(
      dated_post("One", 3.years.ago) + dated_post("Two", 2.years.ago) +
        dated_post("Three", 1.year.ago)
    )

    Blog::Poll.new(blog, fetch: returning(document)).save

    expect(blog.posts.where(received_at: Blog::Poll::FIRST_POLL_WINDOW.ago..).count).to eq(0)
  end
end
