# One image a newsletter hotlinks, fetched by this server at ingest so the
# reader's browser never asks the sender for it.
#
# The fetch itself is Download's — redirects, byte cap, wall clock, and the
# refusal to reach anywhere private. What is left here is the policy: how big
# an image may be, and which types are worth asking for at all.
class Newsletter::ImageDownload
  MAX_BYTES = 5.megabytes

  def initialize(url, resolver: Download::Destination::RESOLVER)
    @url = url
    @resolver = resolver
  end

  # A Download::Body, which answers #bytes and #content_type, or nothing when
  # the fetch found no image this app would serve. Named for what the caller
  # wanted rather than for what came back.
  #
  # Nothing here sends a validator, so a 304 is a server answering a question
  # it was not asked — but it still arrives as the not-modified marker, and a
  # caller that tried to read bytes off that would fail the whole job. There
  # is no image either way.
  def image
    body = download.body
    return if body.equal?(Download::UNCHANGED)

    body
  end

  private

  attr_reader :url, :resolver

  # The same allowlist Newsletter::InlineImages applies to a stored blob, and
  # applied before the body is read rather than after: an image this app would
  # refuse to serve is not worth spending five megabytes to receive.
  def download
    Download.new(url, max_bytes: MAX_BYTES, resolver: resolver,
      types: Newsletter::InlineImages::DISPLAYABLE_TYPES)
  end
end
