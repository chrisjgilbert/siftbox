# The feed a page says it has.
#
# Readers know their blogs by their home pages, not by their feed addresses —
# so pasting queryplanweekly.dev has to work as well as pasting the feed. This
# is the half of that which reads the page; Blog::Subscription is what decides
# to look and what to do with the answer.
#
# Takes the document and the address it came from, rather than fetching:
# fetching is Blog::Fetch's, and keeping the two apart is what lets every
# example against this be a string.
class Blog::FeedLink
  # What a page calls a feed when it announces one. application/xml and
  # text/xml are here because plenty of hand-rolled pages use them, and a
  # document that turns out not to be a feed is refused by the next step
  # anyway — which is the right place for that to be decided.
  TYPES = %w[
    application/atom+xml application/rdf+xml application/rss+xml
    application/xml text/xml
  ].freeze

  def initialize(document, page_url)
    @document = document
    @page_url = page_url
  end

  # The first feed the page announces, or nothing. First rather than best:
  # WordPress writes the post feed and then the comments feed, in that order,
  # and the reader meant the first one.
  def url
    announced.filter_map { |link| fetchable(link["href"]) }.first
  end

  private

  attr_reader :document, :page_url

  def announced
    parsed.css("link[rel~='alternate'][type]")
      .select { |link| TYPES.include?(link["type"].to_s.strip.downcase) }
  end

  # Resolved against the page it was found on, because most pages write a path
  # rather than a whole address and a path means nothing without it.
  #
  # Checked for scheme afterwards rather than before: the address is written
  # by the same stranger the feed is, and it is what gets fetched next.
  # Download refuses anything that is not http or https at every hop, so this
  # is not the guard — it is so a page announcing `javascript:` puts nothing
  # on the roster rather than a row that can never be polled.
  def fetchable(href)
    address = URI.join(page_url, href.to_s).to_s
    return unless address.match?(Blog::FETCHABLE)

    address
  rescue URI::Error
    nil
  end

  def parsed
    @_parsed ||= Nokogiri::HTML5(document.to_s)
  end
end
