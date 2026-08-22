# One request for one blog's feed, and what came back.
#
# The fetch itself is Download's — redirects, the wall clock, and the refusal
# to reach anywhere private, which matters here even though the address is the
# reader's rather than a stranger's: a blog is free to redirect, and a
# redirect inside this network is the same forgery whoever typed the URL.
#
# What is left here is what is true of feeds rather than of fetches: how big
# one may be, that the bytes have to be read as UTF-8, and that a feed polled
# every hour should be asked whether it has changed before it is asked for.
class Blog::Fetch
  # Twenty megabytes against the five an image gets. A feed carries an archive
  # where an image carries one picture, and the measurement in
  # docs/blogs-rss.md found a real one at 11.2MB — so borrowing the image cap
  # would have silently refused a legitimate blog.
  MAX_BYTES = 20.megabytes

  # No content-type allowlist. Feeds are served as application/rss+xml,
  # application/atom+xml, application/xml, text/xml, application/rdf+xml, and
  # by plenty of servers as text/html or application/octet-stream — so the
  # type says too little to refuse on, and Blog::Feed is what decides whether
  # what arrived is really a feed.
  Fetched = Data.define(:document, :etag, :last_modified)

  # The feed has not changed since the validators we sent. Distinct from both
  # a document and a failure, because a poll that gets this has succeeded and
  # has nothing to store.
  UNCHANGED = Data.define.new.freeze

  def initialize(blog, resolver: Download::Destination::RESOLVER)
    @blog = blog
    @resolver = resolver
  end

  # A Fetched, or UNCHANGED, or nothing at all — which is a failure, and
  # Blog::Poll is what decides whether a blog that keeps answering nothing is
  # worth telling the reader about.
  def result
    body = download.body
    return UNCHANGED if body.equal?(Download::UNCHANGED)
    return if body.nil?

    fetched(body)
  end

  private

  attr_reader :blog, :resolver

  def download
    Download.new(blog.feed_url, max_bytes: MAX_BYTES, headers: validators,
      resolver: resolver)
  end

  # Only what the blog actually has. Sending an empty If-None-Match asks the
  # server to match nothing, which some answer with a 304 and most treat as a
  # malformed header.
  def validators
    {
      "If-None-Match" => blog.etag,
      "If-Modified-Since" => blog.last_modified_header
    }.reject { |_name, value| value.blank? }
  end

  # tidy_bytes rather than a plain force_encoding, and for the reason
  # Newsletter::InboundMessage#utf8 gives: a document tagged as something it
  # is not fails the parser outright, and recoding only the bad runs keeps the
  # accents in a feed that is UTF-8 apart from one stray byte.
  def fetched(body)
    Fetched.new(
      document: utf8(body.bytes), etag: body.etag,
      last_modified: body.last_modified
    )
  end

  def utf8(bytes)
    ActiveSupport::Multibyte::Unicode.tidy_bytes(
      bytes.dup.force_encoding(Encoding::UTF_8)
    )
  end
end
