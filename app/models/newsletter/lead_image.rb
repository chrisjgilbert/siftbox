# The first image a newsletter shows, and the body that is left without it.
#
# The feed renders it as a thumbnail and the reader promotes it above the
# article, wider than the text column — so the reader also needs the body
# with that one image taken out, or it appears twice.
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

  # The one relative form this app writes itself: Newsletter::InlineImages
  # rewrites every cid: reference to this path at ingest, so an inline image
  # can still lead. A sender can forge the shape, but forging it buys nothing
  # — Newsletters::ImagesController only ever serves an image, and answers 404
  # for a blob attached to another newsletter. /newsletters/:id is the route
  # that writes, and this does not match it.
  INLINE_IMAGE_PATH = %r{\A/newsletters/\d+/images/[^/?#]+\z}

  # Takes a Newsletter::Body rather than a string, so the caller decides what
  # that body knows — the reader hands one built with the stored image sizes,
  # and the ingest-time capture hands a bare one, because a size cannot change
  # which image comes first.
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

  # #scrubbed rather than the document's own html: the body applies the stored
  # image sizes on its way out, and it does that over the tree this has just
  # taken the lead image out of.
  #
  # The whole figure goes, not just the image inside it: a <figure> exists to
  # tie an image to its caption, so lifting the image above the article and
  # leaving the figure behind strands the caption mid-body, describing a
  # picture that is no longer beside it.
  # The figure is found before the image is detached, because it is found
  # through the image's own parent. Removing the figure takes the image with
  # it; without one, the image goes on its own.
  def remainder
    (enclosing_figure || node)&.remove
    body.scrubbed
  end

  private

  attr_reader :body

  # Memoised before #remainder detaches it, so #url answers the same either
  # side of the removal and no caller has to know the order. `defined?` rather
  # than `||=`, because a body with no hosted image is a legitimate nil and
  # `||=` would walk the whole tree again on every one of the three calls a
  # single reader render makes.
  def node
    return @_node if defined?(@_node)

    @_node = document.css("img").detect { |image| hosted?(image) }
  end

  # Memoised the same way as #node, and for the same reason: #remainder
  # detaches it, and #caption still has to answer afterwards.
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
  # sender using it as a layout box. Taking that out would delete the rest of
  # its contents from the article — not promoted, not captioned, just gone.
  #
  # Asked of the text rather than the element children, which skip text nodes:
  # a sentence sitting loose beside the image is exactly the content worth
  # keeping, and counting only elements would read it as an empty figure.
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
