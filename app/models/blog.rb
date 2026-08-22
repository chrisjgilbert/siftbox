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
  FETCHABLE = %r{\Ahttps?://}i

  # Cascaded in the database as well, so a delete that goes round Rails still
  # takes the posts with it; declared here for the destroy callbacks on the
  # way out.
  has_many :posts, class_name: "Blog::Post", dependent: :destroy, inverse_of: :blog

  # The unique index behind this is what actually holds — two polls adding the
  # same blog at once both pass the validation and the second insert fails on
  # the index. This is here so the ordinary case reads as a validation failure
  # rather than as a RecordNotUnique out of the database, the way
  # Edition::Citation's does.
  validates :feed_url, presence: true, uniqueness: true, format: { with: FETCHABLE }

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
