# The sender's HTML, reduced to what the reader view will render.
#
# Sanitizing happens at render through Action View's `sanitize`, which returns
# an already-safe string. Nothing here calls `html_safe`, so tuning the
# allowlist below applies to the whole archive with no reprocessing.
class Newsletter::Body
  TAGS = %w[
    a b blockquote br code em figcaption figure h1 h2 h3 h4 hr i img li ol p
    pre s strong table tbody td th thead tr u ul
  ].freeze

  # width and height are here for images this app hosts and has measured,
  # which #apply_stored_sizes sets from the stored blob. Every size the sender
  # wrote is stripped first, so nothing reaches the allowlist that this app
  # did not put there itself.
  ATTRIBUTES = %w[alt height href src title width].freeze

  SIZED_ATTRIBUTES = %w[height width].freeze

  # How much of a body a feed row shows. Here rather than on the mail reader,
  # because a blog post has a snippet and has never been near MIME — this is
  # the pipeline the two ingest paths genuinely share.
  SNIPPET_LENGTH = 120

  # A class method because the text does not always come from a Body: mail
  # prefers its own plain-text part when the sender sent one, and only falls
  # back to reading the HTML.
  #
  # On a word boundary, so the last thing a row shows is a word rather than
  # half of one.
  def self.snippet(text)
    text.truncate(SNIPPET_LENGTH, separator: " ")
  end

  # What the editor is shown, from HTML. Two callers had this expression
  # written out — Blog::Post measures its floor on it and Edition::Prompt
  # quotes from it — and nothing held the two in step, so a post could be
  # judged long enough by one reading and quoted from a different one.
  def self.prose(html)
    Newsletter::Prose.new(new(html)).text
  end

  def initialize(html, dimensions: {})
    @html = html
    @dimensions = dimensions
  end

  # Scrubbed, not sanitized: the allowlist above is applied later, by
  # `sanitize` in NewslettersHelper. Pruning matters because `sanitize`
  # unwraps a <script> or <style> tag but keeps the text inside it, which
  # would otherwise land in the reading view as prose.
  def scrubbed
    sized.to_html
  end

  # Joined on the text nodes rather than read off the tree in one go, because
  # Nokogiri runs them together: "<p>Hello there</p><p>Goodbye now</p>" reads
  # back as "Hello thereGoodbye now", which is a snippet of glued words and a
  # word count a block short each time.
  #
  # Loofah's own #to_text knows which elements are line breakers and would get
  # "<p>a<b>b</b>c</p>" right where this returns "a b c" — but it walks the
  # tree again to do it, and measured nineteen times slower on a table-heavy
  # body. This class is careful about how many passes it makes; a separator
  # inside a word is the price, and it costs a word count, not a rendering.
  #
  # `descendant-or-self::` rather than `.//`, which is not the same thing once
  # a predicate is attached: `.//text()[normalize-space()]` silently drops a
  # text node sitting at the top level of the fragment. The predicate skips
  # the whitespace-only nodes, which are two thirds of them on a real body.
  def text
    document.xpath("descendant-or-self::text()[normalize-space()]")
      .map(&:text).join(" ").squish
  end

  # Public so Newsletter::LeadImage can find and remove the lead image in the
  # same tree #sized then walks. The reader promotes that image above the
  # article, so it has to leave the body before the sizes go on — and
  # re-parsing #scrubbed's output to do it would cost a second Loofah pass
  # over a body that runs to hundreds of kilobytes.
  #
  # The order is load-bearing. TrackingPixelScrubber is the only pass that
  # reads a style attribute, so it runs first; the styles are then dropped
  # before :prune, whose html5lib sanitizer CSS-parses every one of them —
  # several hundred on a real newsletter, all of which `sanitize` deletes a
  # moment later anyway. Pruning last over a style-free tree is roughly half
  # the work of pruning first.
  def document
    @_document ||= Loofah.html5_fragment(html.to_s)
      .scrub!(Newsletter::TrackingPixelScrubber.new)
      .tap { |fragment| fragment.css("[style]").each { |node| node.remove_attribute("style") } }
      .scrub!(:prune)
  end

  private

  attr_reader :html, :dimensions

  # A separate step from #document, because #text is the other caller and a
  # size attribute cannot change what the text says — so a snippet does not
  # pay for a walk over every node in the body.
  #
  # After the scrubber, never before: it reads width and height to recognise
  # a tracking pixel, and stripping them first would blind it to every
  # tracker that declares its size in an attribute rather than in CSS.
  def sized
    @_sized ||= document
      .tap { |fragment| strip_sender_sizes(fragment) }
      .tap { |fragment| apply_stored_sizes(fragment) }
  end

  # Every sender-written size goes, including on images this app hosts. The
  # sender's numbers describe some other client's column, and on a table they
  # fight the reading column, which CSS has already unwrapped to block.
  def strip_sender_sizes(fragment)
    fragment.css("*").each do |node|
      SIZED_ATTRIBUTES.each { |name| node.remove_attribute(name) }
    end
  end

  # Both or neither: a browser reserves space from the ratio of the two, so a
  # width on its own buys nothing and an empty height is markup for no one.
  def apply_stored_sizes(fragment)
    fragment.css("img").each do |node|
      width, height = dimensions[node["src"]]
      next if width.blank? || height.blank?

      node["width"] = width.to_s
      node["height"] = height.to_s
    end
  end
end
