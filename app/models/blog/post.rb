# One post from a blog's feed, stored the way a newsletter is.
#
# The reading columns match Newsletter's on purpose: Newsletter::Body,
# Newsletter::Prose and Newsletter::LeadImage take an HTML string or a Body
# and know nothing about mail, so a post carrying the same column names is
# read by the same code rather than by a second copy of it.
#
# Deliberately without the pen's held_at, dismissed_at and released_at. Those
# exist for the double-opt-in confirmation a subscription mails back, which
# arrives by mail and only by mail; a feed has no confirmation step, so
# copying them here would be three columns nothing ever writes.
class Blog::Post < ApplicationRecord
  # What a feed row renders, mirroring Newsletter::FEED_COLUMNS and for the
  # same reason: bodies run to tens of kilobytes and the archive never touches
  # them. blog_id is here because the row prints the blog's name.
  FEED_COLUMNS = %i[
    id blog_id title snippet url received_at lead_image_url
  ].freeze

  belongs_to :blog, touch: true

  # The column is NOT NULL and that is what actually holds. This is here so an
  # ordinary failure reads as a validation naming the field rather than as a
  # NotNullViolation naming the table — the same division Newsletter makes for
  # the same column.
  validates :received_at, presence: true

  def self.for_feed
    select(FEED_COLUMNS)
  end

  def lead_image?
    lead_image_url.present?
  end
end
