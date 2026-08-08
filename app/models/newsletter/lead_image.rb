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
  # The figure's caption wins over alt text when there is one. A figcaption is
  # what the sender wrote about this picture for someone looking at it; alt is
  # written for someone who cannot see it, and is often the filename.
  def alt
    return "" if node.nil?

    caption.presence || node["alt"].to_s
  end

  # #scrubbed rather than the document's own html: the body applies the stored
  # image sizes on its way out, and it does that over the tree this has just
  # taken the lead image out of.
  #
  # The whole figure goes, not just the image inside it. A <figure> exists to
  # bind an image to its caption, so lifting the image above the article and
  # leaving the figure behind orphans the caption mid-body, describing a
  # picture that is no longer beside it.
  def remainder
    (enclosing_figure || node)&.remove
    body.scrubbed
  end

  private

  attr_reader :body

  # Memoised the same way as #node and for the same reason: #remainder
  # detaches it, and both #alt and #remainder ask.
  def enclosing_figure
    return @_enclosing_figure if defined?(@_enclosing_figure)

    @_enclosing_figure = figure_around(node)
  end

  # Only when the image is all the figure holds. A figure wrapped round more
  # than its own image is the sender using it as a layout box, and removing it
  # would take that other content out of the article with it.
  def figure_around(image)
    return if image.nil?
    return unless image.parent.respond_to?(:name) && image.parent.name == "figure"

    image.parent if only_the_image?(image.parent, image)
  end

  def only_the_image?(figure, image)
    figure.element_children.all? do |child|
      child == image || child.name == "figcaption"
    end
  end

  def caption
    enclosing_figure&.at_css("figcaption")&.text.to_s.strip
  end

  # Memoised before #remainder detaches it, so #url answers the same either
  # side of the removal and no caller has to know the order. `defined?` rather
  # than `||=`, because a body with no hosted image is a legitimate nil and
  # `||=` would walk the whole tree again on every one of the three calls a
  # single reader render makes.
  def node
    return @_node if defined?(@_node)

    @_node = document.css("img").detect { |image| hosted?(image) }
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
