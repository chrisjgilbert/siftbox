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

  # What an edition's citation renders: the blog's name, and where the post
  # can be read. Mirrors Newsletter::CITATION_COLUMNS — a post's body_html is
  # a whole article, and printing forty citations should not read forty of
  # them.
  CITATION_COLUMNS = %i[id blog_id title url].freeze

  belongs_to :blog, touch: true

  # The column is NOT NULL and that is what actually holds. This is here so an
  # ordinary failure reads as a validation naming the field rather than as a
  # NotNullViolation naming the table — the same division Newsletter makes for
  # the same column.
  validates :received_at, presence: true

  # Tie-broken on id for the reason Newsletter's orderings are: a feed read
  # in one poll stamps every post it found with the same received_at, so
  # without the tie-break a batch reorders between one query and the next.
  def self.oldest_first
    order(received_at: :asc, id: :asc)
  end

  def self.for_citation
    select(CITATION_COLUMNS)
  end

  def self.for_feed
    select(FEED_COLUMNS)
  end

  def lead_image?
    lead_image_url.present?
  end
end
