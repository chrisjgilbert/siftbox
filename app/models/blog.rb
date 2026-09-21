# A blog the reader follows, and where to fetch it from.
#
# The subscription and the fetcher's bookkeeping in one row. Blog::Poll reads
# the etag and the last-modified header off it before asking the publisher for
# the feed again, and writes back what came home.
#
# Not scoped to a user, the way Feed and Subscriptions are not: one reader,
# one roster, and the authentication gate is the scope.
class Blog < ApplicationRecord
  # What a fetch could actually follow. Download::Destination already refuses
  # anything else, and refuses it at every redirect hop — so this is not the
  # SSRF guard. It is here so a roster row that can never be fetched is
  # refused while the reader is standing there, rather than failing silently
  # on every poll forever and reading as a blog that went away.
  #
  # It is also what lets Blog::Post::Presenter end its fallback chain here:
  # the last link a row can be pointed at is one a browser can follow.
  # Anchored at both ends, and \S so the end anchor cannot be reached across a
  # newline: without that a value could carry a valid first line and anything
  # at all behind it. There is no attack through it today — Download would
  # refuse the address and link_to escapes what it renders — but a validation
  # that can be walked past is not one.
  FETCHABLE = %r{\Ahttps?://\S+\z}i

  # Cascaded in the database as well, so a delete that goes round Rails still
  # takes the posts with it; declared here for the destroy callbacks on the
  # way out.
  has_many :posts, class_name: "Blog::Post", dependent: :destroy, inverse_of: :blog

  # Stripped before it is validated or compared, so an address pasted with
  # whatever whitespace came with it is the address the reader meant — and so
  # two rows differing only in a trailing newline cannot both exist.
  normalizes :feed_url, with: ->(value) { value.strip }

  # The unique index behind this is what actually holds — two polls adding the
  # same blog at once both pass the validation and the second insert fails on
  # the index. This is here so the ordinary case reads as a validation failure
  # rather than as a RecordNotUnique out of the database, the way
  # Edition::Citation's does.
  validates :feed_url, presence: true, uniqueness: true, format: { with: FETCHABLE }

  # A blog built from an address somebody offered — a bookmarklet, or a query
  # parameter typed by hand — for the follow form to be drawn from. Blank
  # when what arrived was not an address at all, so a form filled from the
  # outside can only ever be filled with something this app would fetch.
  #
  # Here rather than at the controller so the rule is stated once, and in the
  # order a row being saved gets it: normalizes runs on assignment, so the
  # format is checked against what the column would hold. Checked before the
  # strip, an address carrying the whitespace it was copied with was dropped
  # and the reader was shown an empty field with nothing said about why.
  def self.offered(address)
    blog = new(feed_url: address.to_s)

    return new unless blog.feed_url.match?(FETCHABLE)

    blog
  end

  # What to call this blog. A fact about the blog rather than about any page
  # showing one, which is where it kept ending up — the archive row, the
  # sources row and the edition prompt all spelled it out, and the last of
  # those reached through a display presenter to do it.
  #
  # blogs.title defaults to "" and a feed may genuinely publish an empty one:
  # Dan Luu's does. The address it is read from is the only other thing this
  # app knows about it.
  def name
    title.presence || feed_url
  end

  # Muted: still polled, still storing posts, still in the originals archive,
  # and no longer reaching an edition. The same three methods Newsletter::Sender
  # carries, because the Subscriptions page holds both kinds in one roster and
  # a reader mutes either the same way.
  #
  # Not the same as removing. BlogsController#destroy takes the posts and the
  # citations naming them with it; this takes nothing.
  def silenced?
    silenced_at.present?
  end

  # The first muting stands. Pressing a button whose state is not visible is
  # not a second decision, and the roster prints the date the reader decided.
  def silence
    return if silenced?

    update!(silenced_at: Time.current)
  end

  def unsilence
    return unless silenced?

    update!(silenced_at: nil)
  end

  # This poll did not come home with a feed. Here rather than in Blog::Poll
  # because the rule is a fact about the column: the first failure's time
  # survives the ones after it, so the Sources page can say how long a blog
  # has been broken rather than only that it is.
  #
  # Both callers used to write this line themselves — the poll for an ordinary
  # failure, the job for the unforeseen kind — and reading failing_since to
  # decide what to write back is the blog's own business rather than theirs.
  def poll_failed
    update!(polled_at: Time.current, failing_since: failing_since || Time.current)
  end
end
