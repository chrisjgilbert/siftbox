# The images a stored body hotlinks, fetched by this server and re-served from
# it — so the archive keeps its images after the publisher's CDN forgets them,
# and reading tells the publisher nothing.
#
# Takes the record rather than a newsletter. It asks for a body, somewhere to
# attach blobs, and a path to serve them from, and every one of those is as
# true of a blog post as of mail: this lived under Newsletter:: only because
# mail was the first thing to need it, which is exactly why the second ingest
# path shipped without it.
#
# Runs off the ingest path, in RemoteImagesJob: a download that fails costs
# the reader nothing, because the src is left pointing where it already
# pointed.
class RemoteImages
  # Nothing about an inbound message or a feed item bounds how many <img> tags
  # it carries, and each one costs a request with its own timeouts and up to
  # MAX_BYTES of disk — fetched one after another, on a queue three threads
  # wide. Without a ceiling the publisher decides how long this app's worker
  # is busy for. Past it a source keeps its original URL, which is what a
  # download that fails does anyway.
  MAX_IMAGES = 100

  DOWNLOAD = ->(url) { Newsletter::ImageDownload.new(url).image }

  def initialize(record, download: DOWNLOAD)
    @record = record
    @download = download
  end

  # The attachments and the body are one write: a record carrying images its
  # body never mentions is a leak nothing later cleans up. The downloads
  # themselves stay outside, because holding a transaction open across a
  # hundred requests to the public internet is worse than either failure.
  def attach
    return if stored.empty?

    record.transaction do
      record.inline_images.attach(*stored.values)
      record.update!(body_html: rewritten_html)
    end
  end

  private

  attr_reader :record, :download

  # Each source fetched once, however often the body repeats it. Keyed on the
  # source as the publisher wrote it, because that is what the rewrite below
  # has to find. A source the download refuses is absent from here, so the
  # body keeps the original URL and the reader still sees the image.
  def stored
    @_stored ||= sources.filter_map { |source| upload(source) }.to_h
  end

  def upload(source)
    image = download.call(fetchable(source))
    return if image.nil?

    [ source, blob_for(source, image) ]
  end

  # A protocol-relative source takes its scheme from the page, which for this
  # app is always https. Older newsletter templates and feed generators both
  # still write them.
  def fetchable(source)
    return "https:#{source}" if source.start_with?("//")

    source
  end

  def blob_for(source, image)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image.bytes),
      filename: filename_for(source, image),
      content_type: image.content_type
    )
  end

  # Active Storage will not accept a blank filename, and the last path segment
  # of a CDN URL is often not one. The extension then follows the type the
  # server served, which is what the blob is stored as anyway.
  def filename_for(source, image)
    name = File.basename(source.split(/[?#]/).first.to_s)
    return name if File.extname(name).present?

    "image.#{extension_for(image)}"
  end

  def extension_for(image)
    Mime::Type.lookup(image.content_type.to_s)&.symbol || "bin"
  end

  # Parsed to find the sources, but never serialised back: the publisher's own
  # markup is what the view-original screen renders, so the body is edited as
  # text below.
  def sources
    document.css("img[src]").map { |node| node["src"] }
      .uniq.select { |source| remote?(source) }.first(MAX_IMAGES)
  end

  def document
    @_document ||= Loofah.html5_fragment(record.body_html.to_s)
  end

  # Leaves alone the paths this app already serves — which is what
  # Newsletter::InlineImages rewrote the cid: references into — and images
  # the message embedded as data URIs.
  def remote?(source)
    source.start_with?("http://", "https://", "//")
  end

  # One pass over the body, as in Newsletter::InlineImages: a gsub per image
  # would copy the whole markup again each time.
  def rewritten_html
    record.body_html.gsub(pattern) { |found| replacements.fetch(found) }
  end

  # The lookbehind is what keeps a protocol-relative spelling inside its own
  # attribute: //host/x.png is the tail of https://host/x.png, so without it
  # a link to the same image anywhere else in the body comes out as
  # "https:" glued to a path this app serves.
  def pattern
    /(?<!:)#{Regexp.union(replacements.keys)}/
  end

  # Longest first, so a URL that is a prefix of another cannot claim its
  # match — alternation takes the first branch that fits, not the best one.
  def replacements
    @_replacements ||= stored
      .flat_map { |url, blob| spellings(url, record.inline_image_path(blob)) }
      .sort_by { |spelling, _path| -spelling.length }
      .to_h
  end

  # Nokogiri answers a decoded attribute; the body holds what the publisher
  # wrote. CDN URLs carry query strings, so an escaped ampersand is the
  # ordinary case rather than the exotic one.
  def spellings(url, path)
    [ [ url, path ], [ CGI.escapeHTML(url), path ] ]
  end
end
