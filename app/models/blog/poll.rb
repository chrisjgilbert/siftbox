require "digest"

# One visit to one blog's feed: read it, and store the posts that are new.
#
# Deliberately shaped like Newsletter::InboundMessage, because it is the same
# job on the other ingest path — read something from outside, store what is
# new, be idempotent about the rest. A poll runs hourly against a feed that
# mostly has not changed, so storing nothing is the ordinary outcome rather
# than the exceptional one.
#
# The fetch is injected the way Newsletter::RemoteImages injects its
# download, so a spec hands over a string instead of standing up a server.
class Blog::Poll
  # How far back a post can be published and still count as new on the day a
  # blog is added. A feed carries a back catalogue rather than only what has
  # changed, so without a bound the first poll of a blog with years of archive
  # puts all of it into tomorrow morning's edition.
  #
  # A week rather than a day, which is what Edition::Window's own first window
  # uses: a blog that publishes on Sundays should not arrive silent because it
  # was subscribed to on a Tuesday. It is also the archive's own horizon, so
  # what an edition may cover on day one is what the archive is showing.
  FIRST_POLL_WINDOW = 1.week

  def initialize(blog, fetch:)
    @blog = blog
    @fetch = fetch
    # Read before anything is written, because #save stamps polled_at and the
    # answer has to be the one that was true when the poll started.
    @first_poll = blog.polled_at.nil?
  end

  # The posts stored, which is usually none: a feed polled hourly has mostly
  # not changed since the last visit.
  #
  # One transaction, so a blog that records having been polled has the posts
  # that poll found. Without it a failure between the two leaves polled_at
  # stamped and the posts missing — and the next poll, no longer a first one,
  # would date the back catalogue it re-reads as though it had just arrived.
  def save
    blog.transaction do
      stored.tap { blog.update!(polled_at: Time.current) }
    end
  end

  private

  attr_reader :blog, :fetch, :first_poll

  def stored
    unseen.map { |post| blog.posts.create!(attributes_for(post)) }
  end

  # uniq before the reject, not after: a feed that lists the same post twice —
  # a generator bug, or a post edited into a second entry — otherwise passes
  # both copies to the index, which refuses the second. That rolls the
  # transaction back and takes polled_at with it, so the blog fails the same
  # way on every poll afterwards and never stores anything again.
  def unseen
    posts.uniq { |post| key_for(post) }
      .reject { |post| known.include?(key_for(post)) }
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

  # When this app first saw the post, which is the axis an edition window
  # runs on — deliberately not the same clock as published_at, which is the
  # publisher's claim and can be years old.
  #
  # A back-dated post on a first poll takes its publication date, which is
  # far below any watermark, so it lands in the archive and no edition ever
  # covers it. Every other post takes now.
  def received_at_for(post)
    return Time.current unless first_poll
    return Time.current if demonstrably_new?(post)

    post.published_at || FIRST_POLL_WINDOW.ago
  end

  # Note which way round this is. A post is admitted on a first poll only when
  # it can be shown to be recent, rather than being admitted unless it can be
  # shown to be old — because an undated post cannot be shown to be either,
  # and a feed with no dates at all is an ordinary shape: RSS 1.0 without
  # dc:date, and plenty of hand-rolled feeds. Read the other way round, one
  # such blog takes its whole archive into the next morning's edition, which
  # is the failure the window exists to prevent.
  #
  # The undated ones are dated at the window's own floor, which is as old as
  # this guard ever needs anything to be.
  def demonstrably_new?(post)
    post.published_at.present? && post.published_at >= FIRST_POLL_WINDOW.ago
  end

  # One query rather than one per post: a feed carries tens of items and most
  # polls store none of them.
  def known
    @_known ||= blog.posts.pluck(:guid)
  end

  def attributes_for(post)
    {
      title: post.title, url: post.url, guid: key_for(post),
      body_html: post.body_html, published_at: post.published_at,
      received_at: received_at_for(post)
    }
  end

  def posts
    Blog::Feed.new(fetch.call(blog)).posts
  end
end
