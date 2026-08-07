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

  ATTRIBUTES = %w[alt href src title].freeze

  def initialize(html)
    @html = html
  end

  # Scrubbed, not sanitized: the allowlist above is applied later, by
  # `sanitize` in NewslettersHelper. Pruning matters because `sanitize`
  # unwraps a <script> or <style> tag but keeps the text inside it, which
  # would otherwise land in the reading view as prose.
  def scrubbed
    document.to_html
  end

  def text
    document.text.squish
  end

  private

  attr_reader :html

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
end
