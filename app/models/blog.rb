# A blog the reader follows, and where to fetch it from.
#
# The subscription and the fetcher's bookkeeping in one row. Blog::Poll reads
# the etag and the last-modified header off it before asking the publisher for
# the feed again, and writes back what came home.
#
# Not scoped to a user, the way Feed and Subscriptions are not: one reader,
# one roster, and the authentication gate is the scope.
class Blog < ApplicationRecord
  # The unique index behind this is what actually holds — two polls adding the
  # same blog at once both pass the validation and the second insert fails on
  # the index. This is here so the ordinary case reads as a validation failure
  # rather than as a RecordNotUnique out of the database, the way
  # Edition::Citation's does.
  validates :feed_url, presence: true, uniqueness: true
end
