# One line of the feed: a newsletter, and where it sits in the index.
#
# The number belongs here rather than on Newsletter::Presenter because it is a
# property of the position, not of the newsletter. It runs continuously across
# the whole feed rather than restarting per group, so the archive reads as an
# index.
class Feed::Row
  delegate :kind, :link_attributes, :lead_image?, :lead_image_url, :path, :sender,
    :snippet, :subject, :timestamp, to: :presenter

  def initialize(presenter, position)
    @presenter = presenter
    @position = position
  end

  # The lead item and a standard row differ in shape, not just in size — one
  # carries a full-width image above the text, the other a thumbnail beside
  # it — so they are two templates rather than one with a branch in it.
  def to_partial_path
    return "newsletters/lead" if lead?

    "newsletters/row"
  end

  def number
    format("%02d", position)
  end

  # The newest item in the feed is number one, and by definition sits in the
  # newest group. With no image it falls back to a standard row — full-width
  # treatment around a placeholder reads as a broken page.
  def lead?
    position == 1 && lead_image?
  end

  private

  attr_reader :presenter, :position
end
