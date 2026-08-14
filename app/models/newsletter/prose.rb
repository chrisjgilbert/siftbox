# What the AI editor is given to read: the newsletter with its markup taken
# off and the boilerplate every issue carries taken out.
#
# Built on Newsletter::Body rather than on body_html, the same way
# Newsletter::LeadImage and Newsletter::ReadingTime are, so the editor pays
# for one Loofah pass over a body that runs to hundreds of kilobytes — and so
# the tracking pixels are already gone when this reads it. Nothing here
# mutates the tree; Body#document is shared, and LeadImage detaches nodes
# from it.
class Newsletter::Prose
  # Everything not named here starts a new line. An allowlist of block
  # elements would read better, but it fails in the wrong direction: an
  # element nobody listed would then run two blocks together into
  # "Read moreIssue 42", and email HTML is full of elements nobody lists.
  # Guessing "block" for an unknown element costs a line break in the middle
  # of a sentence, which the editor reads through.
  INLINE_ELEMENTS = %w[
    a abbr b big cite code em font i mark q s small span strike strong sub sup
    time tt u var
  ].freeze

  # Invisible in a mail client and not whitespace, so squish leaves them.
  # Substack pads a preheader out to the width of an inbox preview with
  # hundreds of them, which arrive here as a line of junk tokens.
  # Escapes rather than the characters themselves, which would leave this
  # line looking like an empty string to everyone who reads it afterwards.
  ZERO_WIDTH = "\u200B\u200C\u200D\uFEFF".freeze

  # A URL is a token the editor cannot follow and must not invent from, so it
  # goes even though the text around it stays. Written as "everything up to
  # the next space" deliberately: it eats a trailing full stop along with the
  # URL, which is a cheaper mistake than leaving half a tracking URL behind.
  URL = %r{\bhttps?://\S+|\bwww\.\S+}i

  def initialize(body)
    @body = body
  end

  def text
    @_text ||= lines.join("\n")
  end

  private

  attr_reader :body

  def lines
    segments.chunk { |node| line_start(node) }
      .map { |_element, nodes| line(nodes) }
      .reject(&:blank?)
  end

  # Whitespace-only text nodes are kept, where Newsletter::Body#text drops
  # them for the two thirds of the tree they are. It joins on a space and can
  # afford to lose them; this joins on nothing, so the space between
  # `<a>Foo</a> <a>Bar</a>` is the only thing standing between two items of a
  # link roundup and "FooBar".
  #
  # `<br>` comes back in the same list so it can be read as the space it is.
  # Nothing else needs the elements: an image contributes no text, and a link
  # contributes its text and not its href.
  def segments
    body.document.xpath("descendant-or-self::text() | descendant-or-self::br")
  end

  def line(nodes)
    clean(nodes.map { |node| segment(node) }.join)
  end

  def segment(node)
    return " " if node.name == "br"

    node.text
  end

  def clean(line)
    line.delete(ZERO_WIDTH).gsub(URL, "").squish
  end

  # The nearest ancestor that is not inline markup — the block this run of
  # text belongs to, and so the line it lands on. Consecutive segments
  # sharing one are one line; a nested block interrupts its parent and takes
  # the next line, which is what a table cell or a list item should do.
  def line_start(node)
    element = node.parent
    element = element.parent while INLINE_ELEMENTS.include?(element.name)
    element
  end
end
