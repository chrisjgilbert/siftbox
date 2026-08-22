require "rss"

# One fetched feed document, read as posts.
#
# RSS and Atom carry the same four facts under different names, and the rss
# gem hands each format back in its own shape: RSS answers plain strings,
# Atom answers elements holding their value under #content or #href. This is
# the whole of the translation, so nothing downstream has to know which
# format a blog publishes.
#
# Takes the document rather than a URL. Fetching is Blog::Poll's job, and
# keeping the two apart is what lets every example against this be a string.
class Blog::Feed
  # Tried in order, and the order prefers the fuller text. A blog publishing
  # in full puts the article in content:encoded (RSS) or content (Atom) and
  # leaves a summary in the other field, so reading the wrong one hands the
  # editor a blurb — which it then reports as a stub, honestly and wrongly.
  BODY_FIELDS = %i[content_encoded content description summary].freeze

  # Atom has two dates and only `updated` is required, so a feed that never
  # sets `published` still dates its posts.
  DATE_FIELDS = %i[pubDate published updated].freeze

  # The document could not be parsed. Feed XML is written by strangers and
  # arrives over the public internet, so this is an ordinary Tuesday rather
  # than an exceptional case — Blog::Poll decides what a blog that sends one
  # is worth, and nothing here does.
  #
  # An entity bomb arrives as one of these: REXML bounds expansion by default,
  # so ten million characters of &a; stop at the parser rather than in memory.
  # Its other refusal is quieter and raises nothing — an external entity is
  # never resolved, so `&secret;` stays six characters of text instead of
  # becoming a file off this server. Both are defaults rather than settings
  # this app chose, which is exactly why the specs pin them.
  Malformed = Class.new(StandardError)

  # Off, and not because strictness is wrong in principle. The parser
  # validates the whole document, so one field it dislikes discards every post
  # in it — and the fields real feeds get wrong are the ones nobody notices,
  # like an ISO-8601 date in RSS 2.0's RFC-822 pubDate, which every other
  # reader accepts. A blog whose generator is a little loose would be
  # unreadable forever rather than for one post, and indistinguishable from a
  # blog that had simply gone away.
  #
  # It costs nothing that matters: the same documents still parse, that date
  # still comes back as a Time, and the entity bomb is still refused — the
  # specs below pin all three.
  VALIDATE = false

  Item = Data.define(:title, :url, :body_html, :published_at)

  def initialize(document)
    @document = document
  end

  def posts
    parsed.items.map { |item| item_from(item) }
  end

  private

  attr_reader :document

  def item_from(item)
    Item.new(
      title: value_of(item.title).to_s, url: value_of(item.link).to_s,
      body_html: first_of(item, BODY_FIELDS).to_s,
      published_at: first_of(item, DATE_FIELDS)
    )
  end

  # RSS hands back the value itself; Atom hands back an element holding it,
  # under #content for text and #href for a link.
  def value_of(field)
    return field.content if field.respond_to?(:content)
    return field.href if field.respond_to?(:href)

    field
  end

  # respond_to? rather than a check on the document's format: which fields an
  # item has is exactly what differs between the two, so asking the item is
  # asking the real question.
  #
  # Unwrapped before it is judged empty, and that order is load-bearing.
  # Publishing tools emit an empty content:encoded or <content/> for a post
  # that has none, and on the Atom side that arrives as a perfectly present
  # element holding an empty string — so asking the element whether it is
  # blank answers no, the preference stops there, and the editor is handed
  # nothing while a real summary sits in the next field along.
  def first_of(item, fields)
    found = fields.filter_map do |field|
      value_of(item.public_send(field)) if item.respond_to?(field)
    end

    found.detect(&:present?)
  end

  def parsed
    @_parsed ||= read
  end

  # Every RSS::Error becomes one error of ours, because the distinction the
  # gem draws — not well formed, unknown version — is not one any caller here
  # can act on differently.
  #
  # ArgumentError and TypeError are here because they arrive from inside the
  # parser rather than from it: bytes tagged as an encoding they are not raise
  # the first, and a document that is not a string raises the second. Neither
  # is an RSS::Error, so both would otherwise walk past a rescue written for
  # the parser's own errors and out through a caller expecting one thing.
  #
  # The nil is the case a rescue alone misses, and it is the likeliest of the
  # lot: the parser answers nothing rather than raising when a document is
  # well-formed XML it does not recognise. A blog that moves and leaves an SPA
  # fallback behind, a parked domain, a WAF interstitial — all serve HTML with
  # a 200, and without this they reach the caller as a NoMethodError on nil
  # instead of as the one error this class promises.
  def read
    feed = RSS::Parser.parse(document, VALIDATE)
    return feed if feed

    raise Malformed, "the document parsed as XML but is not a feed"
  rescue RSS::Error, ArgumentError, TypeError => error
    raise Malformed, "the feed could not be read: #{error.message}"
  end
end
