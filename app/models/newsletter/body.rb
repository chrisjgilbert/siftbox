# The sender's HTML, reduced to what this app reads off it.
#
# The reduction happens here, when the body is read, and not at render time:
# nothing this produces is rendered as markup anywhere. What it feeds is the
# snippet, the prose the editor is shown and the lead image. The one surface
# that shows a newsletter as it arrived is the sandboxed frame, which serves
# Newsletter::Source and reduces nothing at all.
class Newsletter::Body
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

  def initialize(html)
    @html = html
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

  # Public so Newsletter::LeadImage can pick the lead out of the tree this has
  # already reduced. Handing it the HTML instead would cost a second Loofah
  # pass over a body that runs to hundreds of kilobytes.
  #
  # Pruning is what makes #text safe to read: :prune takes a <script> or
  # <style> element away with the text inside it, and #text reads every text
  # node there is. Left alone, a stylesheet would read back as prose into the
  # snippet and into what the editor is shown.
  #
  # The order is load-bearing. TrackingPixelScrubber is the only pass that
  # reads a style attribute, so it runs first; the styles are then dropped
  # before :prune, whose html5lib sanitizer CSS-parses every one of them —
  # several hundred on a real newsletter, and not one of them survives the
  # prune anyway. Pruning last over a style-free tree is roughly half the
  # work of pruning first.
  def document
    @_document ||= Loofah.html5_fragment(html.to_s)
      .scrub!(Newsletter::TrackingPixelScrubber.new)
      .tap { |fragment| fragment.css("[style]").each { |node| node.remove_attribute("style") } }
      .scrub!(:prune)
  end

  private

  attr_reader :html
end
