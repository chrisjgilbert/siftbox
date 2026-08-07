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
  # which #document sets from the stored blob. Every size the sender wrote is
  # stripped first, so nothing reaches the allowlist that this app did not
  # put there itself.
  ATTRIBUTES = %w[alt height href src title width].freeze

  SIZED_ATTRIBUTES = %w[height width].freeze

  def initialize(html, dimensions: {})
    @html = html
    @dimensions = dimensions
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

  attr_reader :html, :dimensions

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
      .tap { |fragment| resize(fragment) }
  end

  # After the scrubber, never before: it reads width and height to recognise
  # a tracking pixel, and stripping them first would blind it to every
  # tracker that declares its size in an attribute rather than in CSS.
  #
  # Every sender-written size goes, including on images this app hosts. The
  # sender's numbers describe some other client's column, and on a table they
  # fight the reading column, which CSS has already unwrapped to block.
  def resize(fragment)
    fragment.css("*").each do |node|
      SIZED_ATTRIBUTES.each { |name| node.remove_attribute(name) }
    end

    fragment.css("img").each do |node|
      width, height = dimensions[node["src"]]
      next if width.blank?

      node["width"] = width.to_s
      node["height"] = height.to_s
    end
  end
end
