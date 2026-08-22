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
#
# Refer to it by its full name from anywhere else under Blog::. This app
# namespaces compactly — `class Blog::Poll` rather than nested modules — so
# Module.nesting there is [Blog::Poll] alone, a bare `Feed` is not looked for
# in Blog, and lookup falls through to the top-level Feed, which is the
# newsletter archive's collection and an entirely different object.
class Blog::Feed
  # Every field either format puts a post's body in. Deliberately not a
  # preference order: the measurement behind docs/blogs-rss.md found Dan Luu
  # publishing full articles in <summary> — 128 items, median 11,997
  # characters — and Simon Willison publishing short link posts in the same
  # element, so which element carries the article cannot be told from its
  # name. The longest of them is taken instead, which is the only rule that
  # does not amount to guessing.
  BODY_FIELDS = %i[content_encoded content description summary].freeze

  # Atom has two dates and only `updated` is required, so a feed that never
  # sets `published` still dates its posts. dc:date is last and is not an
  # afterthought: RSS 1.0 has it *instead* of pubDate rather than as well as
  # it, so without it every post from a feed in that format is undated — and
  # published_at is what the archive sorts by and what the first-poll guard
  # reads to decide whether a post is new enough to cover.
  DATE_FIELDS = %i[pubDate published updated dc_date].freeze

  # The document could not be parsed. Feed XML is written by strangers and
  # arrives over the public internet, so this is an ordinary Tuesday rather
  # than an exceptional case — Blog::Poll decides what a blog that sends one
  # is worth, and nothing here does.
  #
  # An entity bomb arrives as one of these: REXML bounds the number of
  # expansions, so a document that would unpack to a million characters stops
  # at the parser rather than in memory.
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

  # Named rather than left to the gem's own search. RSS::Parser picks the
  # first library it can load out of xmlparser, xmlscan and REXML, and only
  # the last of those is what the two refusals below are a property of — so
  # a gem added for some unrelated reason could silently change this app's
  # XML posture. Stating it means that would be a failing build instead.
  PARSER = RSS::REXMLParser

  # The publisher's own name for a post: guid in RSS, id in Atom. Neither is
  # guaranteed, so what a post is identified by when both are absent is
  # Blog::Poll's decision rather than this class's — all it does is surface
  # what the feed said.
  IDENTITY_FIELDS = %i[guid id].freeze

  # How many items this app is willing to read out of one feed.
  #
  # Nothing about a feed bounds how many it carries, and each one costs an
  # HTML parse, a row and an image-fetching job — so without a ceiling the
  # publisher decides how long this app is busy for. Measured: a 16MB feed of
  # 131,000 items took 90 seconds and 445MB, and an accepted one of that shape
  # would insert every row inside a single SQLite write transaction, which is
  # the one write lock the whole app shares.
  #
  # The same reasoning as Newsletter::RemoteImages::MAX_IMAGES, and a ceiling
  # on the outliers rather than a setting real feeds meet: the largest
  # measured for docs/blogs-rss.md is Dan Luu's at 128 items.
  #
  # What is past the cap is a back catalogue. The first-poll guard already
  # keeps anything older than a week out of every edition window, so the items
  # this drops are ones no edition could have covered.
  MAX_ITEMS = 200

  Item = Data.define(:title, :url, :body_html, :published_at, :identity)

  def initialize(document)
    @document = document
  end

  def posts
    parsed.items.first(MAX_ITEMS).map { |item| item_from(item) }
  end

  # What the feed calls itself, and where it says the writing lives. Both are
  # channel-level in RSS and feed-level in Atom, and both arrive in the same
  # two shapes as everything else — a plain string one side, an element with
  # its value inside it the other.
  def title
    value_of(channel.title).to_s
  end

  def site_url
    address_of(channel).to_s
  end

  private

  attr_reader :document

  # RSS hangs the feed's own title and link off <channel>, where Atom puts
  # them at the top of the document. The items are reachable either way, which
  # is why only these two need asking.
  def channel
    return parsed.channel if parsed.respond_to?(:channel)

    parsed
  end

  def item_from(item)
    Item.new(
      title: value_of(item.title).to_s, url: address_of(item).to_s,
      body_html: body_of(item), published_at: first_of(item, DATE_FIELDS),
      identity: first_of(item, IDENTITY_FIELDS).to_s
    )
  end

  # The one link that is the thing itself, for an item or for the feed as a
  # whole. An Atom entry may carry several — the comment feed, the editing
  # endpoint — and Blogger and WordPress both list those *before* the post's
  # own, so taking whichever came first sends the reader to a comments
  # document. Only Atom answers a list, so RSS falls through to its single
  # link untouched.
  #
  # A channel goes through here as well as an item. The permalink tail below
  # is about item guids, and neither RSS::Rss::Channel nor RSS::RDF::Channel
  # answers to :guid — so it returns nothing for a channel and the fallback
  # is the empty string either way.
  def address_of(element)
    return value_of(alternate(element.links) || element.link) if element.respond_to?(:links)

    value_of(element.link).presence || permalink_of(element)
  end

  # RSS 2.0 lets an item carry its address in the guid instead of a link,
  # when the guid is a permalink. Without this such a post has no address at
  # all: nothing for the archive to link to and nothing for the edition to
  # cite.
  #
  # Against false rather than for true, because the spec makes isPermaLink
  # default to true and the parser reports a missing attribute as nil rather
  # than as that default. A bare <guid> is how most feeds using one spell it,
  # so reading nil as no would miss the common case and catch only the feeds
  # that bothered to say what the spec already says.
  def permalink_of(item)
    guid = item.guid if item.respond_to?(:guid)
    return if guid.nil? || guid.isPermaLink == false

    guid.content
  end

  # No rel at all means alternate, per RFC 4287, so both spellings count.
  def alternate(links)
    links.detect { |link| link.rel.nil? || link.rel == "alternate" }
  end

  # RSS hands back the value itself; Atom hands back an element holding it,
  # under #content for text and #href for a link.
  def value_of(field)
    return field.content if field.respond_to?(:content)
    return field.href if field.respond_to?(:href)

    field
  end

  # The fullest text the feed offers, per BODY_FIELDS above.
  def body_of(item)
    bodies = BODY_FIELDS.filter_map do |field|
      html_of(item.public_send(field)) if item.respond_to?(field)
    end

    bodies.select(&:present?).max_by(&:length).to_s
  end

  # Atom marks a plain-text body with type="text", and it is the only field
  # here that is not already markup. Escaped rather than wrapped, and through
  # CGI rather than ERB::Util, because the latter answers a SafeBuffer — and
  # a body written by a stranger is the last string in this app that should
  # be carrying an html_safe flag around with it.
  def html_of(field)
    return value_of(field) unless plain_text?(field)

    CGI.escapeHTML(field.content)
  end

  # RFC 4287 makes text the default, so an absent type is a declaration of
  # plain text rather than an absence of information — and `content` is the
  # only field asked this, so a String answering nil to :type is not one of
  # these. Checked against real feeds before trusting the default: all 120
  # content and summary elements across the five Atom feeds measured for
  # docs/blogs-rss.md say type="html" outright, so no publisher in that sample
  # is relying on untyped meaning markup.
  def plain_text?(field)
    return false unless field.respond_to?(:type)

    field.type.nil? || field.type == "text"
  end

  # A date is a date, so the first the item answers with will do.
  #
  # respond_to? rather than a check on the document's format: which fields an
  # item has is exactly what differs between the two, so asking the item is
  # asking the real question.
  #
  # Unwrapped before it is judged empty, and that order is load-bearing.
  # Publishing tools emit an empty content:encoded or <content/> for a post
  # that has none, and on the Atom side that arrives as a perfectly present
  # element holding an empty string — so asking the element whether it is
  # blank answers no, and an empty string wins on existing alone.
  def first_of(item, fields)
    fields
      .filter_map { |field| value_of(item.public_send(field)) if item.respond_to?(field) }
      .detect(&:present?)
  end

  def parsed
    @_parsed ||= read
  end

  # Every RSS::Error becomes one error of ours, because the distinction the
  # gem draws — not well formed, unknown version — is not one any caller here
  # can act on differently.
  #
  # A document with no angle bracket in it is not an empty feed, it is a
  # location: the parser reads such a string as a path to open or a URL to
  # fetch, and hands back whatever it finds there. What this class is given is
  # the body a stranger's server returned, so without this a server that
  # answers with "/etc/passwd" or "http://169.254.169.254/…" has this app read
  # it — off its own disk, or from inside its own network. Verified rather
  # than assumed: pointed at a path holding a valid feed, the parser returned
  # that file's posts.
  def markup?
    document.is_a?(String) && document.include?("<")
  end

  # ArgumentError is here because it arrives from inside the parser rather
  # than from it: bytes tagged as an encoding they are not raise it, and it is
  # not an RSS::Error, so it would otherwise walk past a rescue written for
  # the parser's own errors and out through a caller expecting one thing.
  # TypeError keeps it company as a backstop rather than for a case anyone can
  # name — the parser raises it for a document that is not a String, and
  # #markup? has already refused those one line earlier.
  #
  # The nil is the case a rescue alone misses, and it is the likeliest of the
  # lot: the parser answers nothing rather than raising when a document is
  # well-formed XML it does not recognise. A blog that moves and leaves an SPA
  # fallback behind, a parked domain, a WAF interstitial — all serve HTML with
  # a 200, and without this they reach the caller as a NoMethodError on nil
  # instead of as the one error this class promises.
  def read
    raise Malformed, "the document carries no markup" unless markup?

    feed = RSS::Parser.parse(document, VALIDATE, true, PARSER)
    return feed if feed

    raise Malformed, "the document parsed as XML but is not a feed"
  rescue RSS::Error, ArgumentError, TypeError => error
    raise Malformed, "the feed could not be read: #{error.message}"
  end
end
