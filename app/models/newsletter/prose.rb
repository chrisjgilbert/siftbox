# What the AI editor is given to read: the newsletter with its markup taken
# off and the boilerplate every issue carries taken out.
#
# Built on Newsletter::Body rather than on body_html, the same way
# Newsletter::LeadImage is, so the editor pays for one Loofah pass over a body
# that runs to hundreds of kilobytes — and so the tracking pixels are already
# gone when this reads it. Nothing here mutates the tree; Body#document is
# shared, and LeadImage detaches nodes from it.
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

  # Chrome is boilerplate every issue of every newsletter carries, and it is
  # not the same thing as anything that reads promotionally. A newsletter
  # whose actual subject is subscription businesses is content, and a
  # paywalled stub's upgrade prompt is the evidence the editor classifies it
  # by — the PRD has it report a teaser honestly rather than write it up, and
  # a stub with its prompt cut out reads as a complete but thin article.
  #
  # So both rules below are anchored rather than a keyword search: a label
  # has to be the whole line, and an opener has to start it. What that misses
  # stays in, which is the right way round — the completeness guarantee means
  # anything dropped here is something the editor can no longer cite.
  #
  # Both lists are matched against the line folded to lower case.
  CHROME_LABELS = [
    /\Aread (in|on)( the)? app\z/,
    /\A(view|read) (this )?(email |message )?(in|on) (your |the )?browser\z/,
    /\A(view|read) (it |this )?online\z/,
    /\Aunsubscribe( here| from this list| from these emails)?\z/,
    /\A(update|manage|edit) (your )?(email |newsletter )?(preferences|subscription|settings)\z/,
    /\A(email|subscription|notification) (preferences|settings)\z/,
    /\Ashare( this)?( post| email| story| newsletter)?\z/,
    /\A(tweet|forward|like|comment|restack|view comments)\z/,
    /\A(facebook|twitter|linkedin|instagram|threads|mastodon|bluesky|whatsapp|telegram|youtube|tiktok|reddit|x)\z/
  ].freeze

  # Sentence-shaped boilerplate, which no length ceiling separates reliably
  # from a short paragraph. Anchored to the start of the line instead: prose
  # mentions these phrases mid-sentence, footers open with them.
  CHROME_OPENERS = [
    /\Aforwarded this (email|message|newsletter)/,
    /\Ayou['’]?(re| are) (receiving|getting) this/,
    /\Ayou (received|are subscribed to)/,
    /\Athis (email|message) was sent to/,
    /\A(if you )?no longer wish to receive/,
    /\A(if you )?no longer want (to receive )?(these|this)/,
    /\Ato (stop receiving|unsubscribe from)/,
    /\A(copyright )?©\s*\d{4}/,
    /\Aall rights reserved/
  ].freeze

  # What a line of labels is separated by. A hyphen only counts with spaces
  # either side, so "opt-in" is one part rather than two.
  SEPARATORS = %r{[|·•⋅/:,]|\s[-–—]\s}

  # An address block ends with its postcode — US state and ZIP, or a UK
  # postcode. Ending there is the whole rule: a street address quoted inside
  # a story has the rest of the sentence after it, and matching on "looks
  # like an address" anywhere in the line would take the story with it.
  #
  # The UK form needs a second anchor. "M2 8GB" is a valid Manchester
  # postcode and also a laptop, so the pattern alone deletes ordinary tech
  # prose — and under the completeness guarantee a dropped line is one the
  # edition can never report. A footer address is written in parts
  # ("Dispatchmail, 41 Blackfriars Road, London SE1 8NZ"), so the comma is
  # what separates it from a sentence that merely ends in the same shape.
  # The US form is specific enough to stand on its own.
  POSTCODE_UNITED_STATES = /[A-Z]{2}\s+\d{5}(?:-\d{4})?/
  POSTCODE_UNITED_KINGDOM = /[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}/
  ADDRESS = Regexp.union(
    /\A.{0,120}\b#{POSTCODE_UNITED_STATES}[.,]?\z/,
    /\A.{0,120},.{0,120}\b#{POSTCODE_UNITED_KINGDOM}[.,]?\z/
  )

  # Roughly three thousand tokens at four characters to a token, which is the
  # PRD's "a few thousand tokens" per newsletter: twenty of them is around
  # sixty thousand tokens of input, tens of cents a day at claude-opus-5's
  # $5 per million. Most issues come in under it whole — a 60KB body is
  # mostly markup — so this is a ceiling on the outliers rather than a
  # setting every newsletter meets. Raising it costs money linearly and
  # buries the short newsletters in the middle of the window; lowering it
  # starts cutting ordinary issues in half.
  MAXIMUM_CHARACTERS = 12_000

  # Named, and named as our doing. A cut that said nothing would be read as
  # the sender's: the editor classifies a paywalled stub partly by where the
  # text stops, and it would report this app's ceiling as somebody's paywall.
  OMISSION = "\n[truncated for length]".freeze

  def initialize(body)
    @body = body
  end

  def text
    @_text ||= capped(lines.join("\n"))
  end

  private

  attr_reader :body

  def lines
    segments.chunk { |node| line_start(node) }
      .map { |_element, nodes| line(nodes) }
      .reject(&:blank?)
      .reject { |line| chrome?(line) }
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

  # On a space, so no word is handed over as a fragment the editor could
  # quote as though the sender had written it.
  def capped(prose)
    prose.truncate(MAXIMUM_CHARACTERS, separator: " ", omission: OMISSION)
  end

  def clean(line)
    line.delete(ZERO_WIDTH).gsub(URL, "").squish
  end

  # The address is read off the line as written, because its postcode is a
  # shape in capitals; everything else reads better folded.
  def chrome?(line)
    folded = line.downcase

    labels_only?(folded) || opener?(folded) || ADDRESS.match?(line)
  end

  # Every part a label, not merely one of them: a footer stacks its links in
  # one row — "Unsubscribe | Update your preferences" — and a sentence with a
  # comma in it is several parts of which the first is prose.
  def labels_only?(folded)
    parts = parts_of(folded)

    parts.any? && parts.all? { |part| label?(part) }
  end

  def parts_of(folded)
    folded.split(SEPARATORS)
      .map { |part| part.gsub(/\A\W+|\W+\z/, "") }
      .reject(&:blank?)
  end

  def label?(part)
    CHROME_LABELS.any? { |pattern| part.match?(pattern) }
  end

  def opener?(folded)
    CHROME_OPENERS.any? { |pattern| folded.match?(pattern) }
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
