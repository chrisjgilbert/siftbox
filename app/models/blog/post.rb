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

  # The images the post hotlinked, fetched by this server at poll time and
  # re-served from it — so the archive keeps its thumbnails after the
  # publisher's CDN forgets them, and reading the archive tells the publisher
  # nothing. Written by RemoteImages, exactly as a newsletter's are.
  has_many_attached :inline_images

  # SQLite stops reading a string literal at a NUL, so one stray byte fails
  # the INSERT and loses the post. The same guard Newsletter carries, for the
  # same reason and against a source no less hostile: feed XML is written by
  # strangers and a NUL survives the parser intact.
  normalizes :body_html, :guid, :snippet, :title, :url,
    with: ->(value) { value.delete("\0") }

  # The column is NOT NULL and that is what actually holds. This is here so an
  # ordinary failure reads as a validation naming the field rather than as a
  # NotNullViolation naming the table — the same division Newsletter makes for
  # the same column.
  validates :received_at, presence: true

  # Tie-broken on id for the reason Newsletter's orderings are: a feed read in
  # one poll stamps every post it found with the same received_at, so without
  # the tie-break a batch reorders between one query and the next.
  #
  # No spec, and deliberately none: SQLite returns ties in rowid order under
  # every plan this query gets — index scan and temp b-tree alike — so an
  # example asserting the result passes with the tie-break deleted. It is kept
  # because the guarantee should not rest on which index the planner reaches
  # for. Where it is genuinely load-bearing is Feed#ordering, which sorts in
  # Ruby, where sort_by is not stable — and that one is specced.
  # Asked of a bare body as well as of a row: Blog::Subscription judges a
  # feed's items before any of them is a record. One statement of the rule, so
  # a feed admitted at the door and a post kept out of an edition cannot
  # disagree about what a body is worth.
  #
  # Measured on the prose the editor would be shown rather than on the HTML,
  # so a post that is markup around nothing is judged on what is left of it.
  def self.enough_to_write_from?(html)
    Newsletter::Body.prose(html).length >= EDITORIAL_MINIMUM
  end

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

  # Read again after RemoteImages has rewritten the body. The lead captured at
  # poll time still points at the publisher's CDN, and left there the archive
  # would hotlink a thumbnail per row on every load — the one request storing
  # the images exists to stop making.
  def capture_lead_image
    update!(lead_image_url: Newsletter::LeadImage.new(Newsletter::Body.new(body_html)).url)
  end

  # This app's own path for a stored image, not Active Storage's: see
  # BlogPosts::ImagesController for why. No route helpers on a model, the way
  # Newsletter has none either.
  def inline_image_path(blob)
    Rails.application.routes.url_helpers.blog_post_image_path(self, blob)
  end

  def enough_to_write_from?
    self.class.enough_to_write_from?(body_html)
  end
end
