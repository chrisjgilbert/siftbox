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
  def first_of(item, fields)
    found = fields.filter_map do |field|
      item.public_send(field) if item.respond_to?(field)
    end

    value_of(found.first)
  end

  # Every RSS::Error becomes one error of ours, because the distinction the
  # gem draws — not well formed, unknown version, missing a required field —
  # is not one any caller here can act on differently.
  def parsed
    @_parsed ||= RSS::Parser.parse(document)
  rescue RSS::Error => error
    raise Malformed, "the feed could not be read: #{error.message}"
  end
end
