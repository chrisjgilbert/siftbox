# Named for Loofah's extension point, the way a background job is named for
# Active Job's. See .claude/rules/models.md on naming.
#
# Runs before the allowlist, while style attributes still exist, so it can
# read a size the sender expressed in CSS as well as in an attribute.
#
# It cannot catch a tracker that declares no size at all — nothing can tell
# that apart from an ordinary image — so this narrows the gap rather than
# closing it. Only re-hosting images would close it. See README.md.
class Newsletter::TrackingPixelScrubber < Loofah::Scrubber
  LARGEST_TRACKING_PIXEL = 2
  SIZE_ATTRIBUTES = %w[width height].freeze

  def initialize
    @direction = :top_down
    super
  end

  def scrub(node)
    return CONTINUE unless node.name == "img"
    return CONTINUE unless tracking_pixel?(node)

    node.remove
    STOP
  end

  private

  def tracking_pixel?(node)
    hidden?(node) || SIZE_ATTRIBUTES.any? { |name| tiny?(dimension(node, name)) }
  end

  # Read up the tree, not just this node. Senders hide the container rather
  # than the image — `<div style="display:none"><img src="…beacon"></div>` —
  # and an <img> one node down reads as ordinary. Left in, a beacon that
  # declares no size wins Newsletter::LeadImage's pick, so it is stored as
  # lead_image_url and fetched again on every feed load: an open tracker
  # turned into a repeat one.
  def hidden?(node)
    ancestry(node).any? { |element| style(element).match?(/display\s*:\s*none/i) }
  end

  def ancestry(node)
    [ node, *node.ancestors ].select(&:element?)
  end

  # The property has to start a declaration. Without that anchor `height`
  # matches inside `line-height` and `max-height`, and `width` inside
  # `max-width` — and `line-height: 0` is on nearly every image in a real
  # newsletter, so an unanchored read deletes the article's photographs.
  def dimension(node, name)
    node[name].presence || style(node)[/(?:\A|[;\s])#{name}\s*:\s*([^;]+)/i, 1]
  end

  def style(node)
    node["style"].to_s
  end

  # An explicit pixel count only. A percentage says nothing about the real
  # size, and most real images carry no dimensions at all.
  def tiny?(value)
    counted = value.to_s.strip[/\A(\d+)(?:px)?\z/i, 1]
    return false if counted.nil?

    counted.to_i <= LARGEST_TRACKING_PIXEL
  end
end
