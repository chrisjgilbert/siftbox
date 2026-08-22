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

  # How much prose a post has to carry before an edition may be written from
  # it. Real blogs publish the occasional stub — a title, a link and two lines
  # — and 9 of the 273 posts measured for docs/blogs-rss.md fell under this,
  # mostly Martin Fowler publishing one essay as a run of linked fragments.
  # Asked to write a lead story from two lines, the editor writes the rest.
  #
  # A floor rather than a guess at what kind of post this is. Length says
  # nothing about whether a feed is truncating — Dan Luu publishes whole
  # articles in <summary> and Simon Willison publishes short posts on purpose
  # — so this only answers whether there is enough here to write from at all.
  EDITORIAL_MINIMUM = 400

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

  # Measured on the same prose the editor would be shown rather than on the
  # HTML, so a post that is markup around nothing is judged on what is left of
  # it. Through the pipeline the prompt uses, for the same reason the snippet
  # goes through it: it takes an HTML string and knows nothing about mail.
  def enough_to_write_from?
    prose.length >= EDITORIAL_MINIMUM
  end

  private

  def prose
    Newsletter::Prose.new(Newsletter::Body.new(body_html)).text
  end
end
