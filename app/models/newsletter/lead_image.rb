# The first image a newsletter shows. Captured at ingest into
# newsletters.lead_image_url, so the feed can render a thumbnail per row
# without loading a body to find one.
#
# Reads Newsletter::Body's document, which means the tracking-pixel scrubber
# has already run: a 1x1 beacon is gone before the first image is picked, and
# cannot win the lead.
class Newsletter::LeadImage
  # An allowlist rather than a denylist, because the cases worth refusing are
  # not all obvious. A cid: reference is an inline image Newsletter::InlineImages
  # failed to rewrite and means nothing to a browser. A data: URI is a spacer
  # or a bullet, and storing one would put kilobytes of base64 into a column
  # the feed reads on every row. And a relative URL points back at this app:
  # a sender who writes `<img src="/newsletters/5">` gets that stored as
  # lead_image_url and fetched by the reader's own browser, with the session
  # cookie attached, on every feed load.
  #
  # Protocol-relative is kept — plenty of older newsletters still use it, and
  # it resolves to the sender's own host the same as https.
  HOSTED_SCHEMES = %w[http:// https:// //].freeze

  # The relative forms this app writes itself, and only those.
  # Newsletter::InlineImages rewrites every cid: reference to the first at
  # ingest, and RemoteImages rewrites a hotlinked source to one or the other
  # once it has fetched it — so a stored image can still lead.
  #
  # A publisher can forge either shape, and forging it buys nothing: both
  # images controllers only ever serve an image, and both answer 404 for a
  # blob attached to another record. Neither pattern matches a route that
  # writes.
  HOSTED_PATHS = %w[blog_posts newsletters].freeze

  INLINE_IMAGE_PATH = %r{\A/(#{Regexp.union(HOSTED_PATHS)})/\d+/images/[^/?#]+\z}

  # The lead in one HTML string, for a caller that holds no Body and wants
  # none. Both records capture their lead with the identical expression, and
  # nothing held the two in step — the same shape Newsletter::Body.prose was
  # hoisted for.
  def self.url_in(html)
    new(Newsletter::Body.new(html)).url
  end

  # Takes a Newsletter::Body rather than a string, so a caller that is already
  # holding one pays for a single Loofah pass — Blog::Poll reads the snippet
  # off the same body it takes the lead from.
  def initialize(body)
    @body = body
  end

  def url
    return "" if node.nil?

    node["src"].to_s
  end

  # Read rather than stored: the reader is the only screen that captions the
  # image, and it already has the body open.
  #
  # Kept separate from #caption rather than merged with it. alt is written for
  # someone who cannot see the picture and a caption for someone who can, and
  # the reader has a slot for each — a photo credit in the alt attribute is no
  # use to a screen reader, and a chart's description reads oddly under it.
  def alt
    return "" if node.nil?

    node["alt"].to_s
  end

  # The figure's caption when there is one, because that is what the sender
  # wrote about this picture. Alt text is the fallback: it is the only other
  # thing the email says about the image, and an empty caption slot under a
  # full-width photograph reads as a rendering fault.
  def caption
    return "" if node.nil?

    figure_caption.presence || node["alt"].to_s
  end

  private

  attr_reader :body

  # `defined?` rather than `||=`, because a body with no hosted image is a
  # legitimate nil and `||=` would walk the whole tree again on every one of
  # the three readers that ask for it.
  def node
    return @_node if defined?(@_node)

    @_node = document.css("img").detect { |image| hosted?(image) }
  end

  # Memoised the same way as #node, and for the same reason: both #caption and
  # the helpers behind it ask for it.
  #
  # Found through the ancestors rather than the image's own parent, because a
  # CMS links the image to its full-size version — `<figure><a><img></a>
  # <figcaption>` — and the parent is then the <a>. That is the shape most of
  # them emit, so reading the parent alone misses the common case entirely.
  def enclosing_figure
    return @_enclosing_figure if defined?(@_enclosing_figure)

    figure = node&.ancestors("figure")&.first
    @_enclosing_figure = figure if figure && holds_only_the_lead?(figure)
  end

  # A figure holding anything besides the lead image and a caption is the
  # sender using it as a layout box, so its caption describes the box rather
  # than the picture and the image's own alt text is the better answer.
  #
  # Asked of the text rather than the element children, which skip text nodes:
  # a sentence sitting loose beside the image is exactly what makes it a box,
  # and counting only elements would read it as an empty figure.
  def holds_only_the_lead?(figure)
    figure.css("img").length == 1 && prose_outside_caption(figure).blank?
  end

  def prose_outside_caption(figure)
    figure.children
      .reject { |child| child.name == "figcaption" }
      .map(&:text).join
  end

  def figure_caption
    enclosing_figure&.at_css("figcaption")&.text.to_s.strip
  end

  def hosted?(image)
    source = image["src"].to_s

    elsewhere?(source) || source.match?(INLINE_IMAGE_PATH)
  end

  def elsewhere?(source)
    HOSTED_SCHEMES.any? { |scheme| source.downcase.start_with?(scheme) }
  end

  def document
    body.document
  end
end
