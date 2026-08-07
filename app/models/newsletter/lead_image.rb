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
  # A cid: reference is an inline image Newsletter::InlineImages failed to
  # rewrite, and means nothing to a browser. A data: URI is a spacer or a
  # bullet, and storing one would put kilobytes of base64 into a column the
  # feed reads on every row.
  UNRESOLVABLE_SCHEMES = %w[cid: data:].freeze

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
  def alt
    return "" if node.nil?

    node["alt"].to_s
  end

  # #scrubbed rather than the document's own html: the body applies the stored
  # image sizes on its way out, and it does that over the tree this has just
  # taken the lead image out of.
  def remainder
    node&.remove
    body.scrubbed
  end

  private

  attr_reader :body

  # Memoised before #remainder detaches it, so #url answers the same either
  # side of the removal and no caller has to know the order.
  def node
    @_node ||= document.css("img").detect { |image| hosted?(image) }
  end

  def hosted?(image)
    source = image["src"].to_s

    source.present? && UNRESOLVABLE_SCHEMES.none? { |scheme| source.start_with?(scheme) }
  end

  def document
    body.document
  end
end
