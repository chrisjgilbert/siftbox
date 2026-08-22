require "digest"

# One visit to one blog's feed: read it, and store the posts that are new.
#
# Deliberately shaped like Newsletter::InboundMessage, because it is the same
# job on the other ingest path — read something from outside, store what is
# new, be idempotent about the rest. A poll runs hourly against a feed that
# mostly has not changed, so storing nothing is the ordinary outcome rather
# than the exceptional one.
#
# The fetch is injected the way Newsletter::RemoteImages injects its download,
# so a spec hands over an answer instead of standing up a server.
class Blog::Poll
  # How far back a post can be published and still count as new on the first
  # poll that stores anything. A feed carries a back catalogue rather than
  # only what has changed, so without a bound the first read of a blog with
  # years of archive puts all of it into tomorrow morning's edition.
  #
  # A week rather than a day, which is what Edition::Window's own first window
  # uses: a blog that publishes on Sundays should not arrive silent because it
  # was subscribed to on a Tuesday. It is also the archive's own horizon, so
  # what an edition may cover on day one is what the archive is showing.
  FIRST_POLL_WINDOW = 1.week

  FETCH = ->(blog) { Blog::Fetch.new(blog).result }

  def initialize(blog, fetch: FETCH)
    @blog = blog
    @fetch = fetch
  end

  # The posts stored, which is usually none: a feed polled hourly has mostly
  # not changed since the last visit.
  #
  # The fetch happens first and outside the transaction. A stalled host holds
  # its connection for up to Download::MAX_DURATION, and holding a database
  # transaction open across that — once per blog, across the roster — is
  # exactly what Newsletter::RemoteImages documents itself as avoiding.
  #
  # What the transaction does wrap is the write, so a blog that records having
  # been polled has the posts that poll found.
  def save
    result = fetch.call(blog)

    blog.transaction { record(result) }
  end

  private

  attr_reader :blog, :fetch

  # Three outcomes and they are genuinely different. A document means read it;
  # unchanged means the poll worked and there is nothing to do; nothing at all
  # means the feed did not answer, which is the failure the reader would
  # otherwise never learn about — a blog that has stopped being fetchable
  # looks exactly like one that has stopped publishing.
  def record(result)
    return failed if result.nil?
    return unchanged if result.equal?(Blog::Fetch::UNCHANGED)

    read(result)
  end

  def failed
    blog.update!(polled_at: Time.current, failing_since: blog.failing_since || Time.current)
    []
  end

  # The validators are left exactly as they were. A 304 says what we hold is
  # current, so what earned it is still the right thing to send next time —
  # clearing them would make every later poll unconditional and undo the only
  # reason for sending them at all.
  def unchanged
    blog.update!(polled_at: Time.current, failing_since: nil)
    []
  end

  # A blog serving something that is not a feed has stopped answering, as far
  # as the reader is concerned. Recorded as the failure it is rather than as a
  # poll that found nothing — otherwise the blog reads as healthy forever
  # while storing nothing, and keeps the validators that would let the next
  # poll 304 without ever looking at the body again.
  def read(result)
    feed = Blog::Feed.new(result.document)
    posts = stored(feed)
    succeeded(feed, result)
    posts
  rescue Blog::Feed::Malformed
    failed
  end

  # failing_since is cleared rather than left, so the Sources page stops
  # saying a blog is broken the moment it is not. The first failure's time is
  # kept while it lasts, which is what lets the page say how long.
  #
  # The name and address come from the feed on every read rather than only
  # once: the feed is the only thing that knows them, and nothing else writes
  # them today. That changes the day the reader can rename a blog.
  def succeeded(feed, result)
    blog.update!(
      polled_at: Time.current, failing_since: nil, title: feed.title,
      site_url: feed.site_url, etag: result.etag, last_modified_header: result.last_modified
    )
  end

  def stored(feed)
    unseen(feed).map { |post| blog.posts.create!(attributes_for(post)) }
  end

  # uniq before the reject, not after: a feed that lists the same post twice —
  # a generator bug, or a post edited into a second entry — otherwise passes
  # both copies to the index, which refuses the second. That rolls the
  # transaction back and takes polled_at with it, so the blog fails the same
  # way on every poll afterwards and never stores anything again.
  def unseen(feed)
    feed.posts
      .uniq { |post| key_for(post) }
      .reject { |post| known.include?(key_for(post)) }
  end

  def attributes_for(post)
    body = Newsletter::Body.new(post.body_html)

    {
      title: post.title, url: post.url, guid: key_for(post),
      body_html: post.body_html, published_at: post.published_at,
      received_at: received_at_for(post), snippet: snippet_of(body),
      lead_image_url: Newsletter::LeadImage.new(body).url
    }
  end

  # Both read off the stored body by the pipeline that already exists. It
  # takes an HTML string and knows nothing about mail, which is the whole
  # reason blog_posts carries the same column names newsletters does — a post
  # is read by that code rather than by a second copy of it.
  #
  # One Body between them, because it holds the parsed tree: building two
  # would walk a body that runs to tens of kilobytes twice for one row.
  def snippet_of(body)
    body.text.truncate(Newsletter::InboundMessage::SNIPPET_LENGTH, separator: " ")
  end

  # What "seen this one before" is decided on: the publisher's own name for
  # the post, then its address, then a digest of what little is left.
  #
  # Never empty, and that is the point of the chain rather than a nicety. An
  # empty string is not an identity, and storing one as though it were makes
  # the first post a blog publishes without a guid the last one it can ever
  # publish — every later unnamed post matches it and is skipped as seen.
  def key_for(post)
    post.identity.presence || post.url.presence || digest_of(post)
  end

  # Deterministic, which is the whole requirement: reading the same post next
  # hour has to compute the same key. Anything generated rather than derived
  # would make every poll store every post again.
  def digest_of(post)
    Digest::SHA256.hexdigest([ post.title, post.published_at ].join("\n"))
  end

  # When this app first saw the post, which is the axis an edition window runs
  # on — deliberately not the same clock as published_at, which is the
  # publisher's claim and can be years old.
  def received_at_for(post)
    return Time.current unless first_poll?
    return Time.current if demonstrably_new?(post)

    post.published_at || FIRST_POLL_WINDOW.ago
  end

  # Note which way round this is. A post is admitted on a first poll only when
  # it can be shown to be recent, rather than being admitted unless it can be
  # shown to be old — because an undated post cannot be shown to be either,
  # and a feed with no dates at all is an ordinary shape: RSS 1.0 without
  # dc:date, and plenty of hand-rolled feeds. Read the other way round, one
  # such blog takes its whole archive into the next morning's edition.
  #
  # The undated ones are dated at the window's own floor, which is as old as
  # this guard ever needs anything to be.
  def demonstrably_new?(post)
    post.published_at.present? && post.published_at >= FIRST_POLL_WINDOW.ago
  end

  # Whether anything has ever been stored, rather than whether the blog has
  # ever been visited. A first fetch that failed still stamps polled_at, so
  # keying on that would drop the guard for a blog whose back catalogue this
  # app has never actually read — and the moment it recovered, all of it would
  # pour into the next edition.
  def first_poll?
    known.empty?
  end

  # One query rather than one per post: a feed carries tens of items and most
  # polls store none of them. Read before anything is written, so it also
  # answers what was true when the poll started.
  def known
    @_known ||= blog.posts.pluck(:guid)
  end
end
