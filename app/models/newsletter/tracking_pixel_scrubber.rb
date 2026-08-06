# Named for Loofah's extension point, the way a background job is named for
# Active Job's. See .claude/rules/models.md on naming.
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
    SIZE_ATTRIBUTES.any? { |attribute| tiny?(node[attribute]) }
  end

  # Only an explicit pixel count counts. A percentage or a missing attribute
  # says nothing about the real size, and most real images carry neither.
  def tiny?(value)
    return false unless value.to_s.match?(/\A\d+\z/)

    value.to_i <= LARGEST_TRACKING_PIXEL
  end
end
