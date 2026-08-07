# The images a newsletter hotlinks, stored the way Newsletter::InlineImages
# stores the ones the message carried inside it — so the archive keeps its
# images after the sender's CDN forgets them, and opening a newsletter tells
# the sender nothing.
#
# Runs off the ingest path, in Newsletter::RemoteImagesJob: a download that
# fails costs the reader nothing, because the src is left pointing where it
# already pointed.
class Newsletter::RemoteImages
  DOWNLOAD = ->(url) { Newsletter::ImageDownload.new(url).image }

  def initialize(newsletter, download: DOWNLOAD)
    @newsletter = newsletter
    @download = download
  end

  def attach
    return if stored.empty?

    newsletter.inline_images.attach(*stored.values)
    newsletter.update!(body_html: rewritten_html)
  end

  private

  attr_reader :newsletter, :download

  # Each source fetched once, however often the body repeats it. A source
  # the download refuses is absent from here, so the body keeps the sender's
  # URL and the reader still sees the image.
  def stored
    @_stored ||= sources.filter_map { |url| upload(url) }.to_h
  end

  def upload(url)
    image = download.call(url)
    return if image.nil?

    [ url, blob_for(url, image) ]
  end

  def blob_for(url, image)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image.bytes),
      filename: filename_for(url, image),
      content_type: image.content_type
    )
  end

  # Active Storage will not accept a blank filename, and the last path
  # segment of a CDN URL is often not one. The extension then follows the
  # type the sender served, which is what the blob is stored as anyway.
  def filename_for(url, image)
    name = File.basename(url.split(/[?#]/).first.to_s)
    return name if File.extname(name).present?

    "image.#{extension_for(image)}"
  end

  def extension_for(image)
    Mime::Type.lookup(image.content_type.to_s)&.symbol || "bin"
  end

  # Parsed to find the sources, but never serialised back: the sender's own
  # markup is what the view-original screen renders, so the body is edited
  # as text below.
  def sources
    document.css("img[src]").map { |node| node["src"] }.uniq.select { |src| remote?(src) }
  end

  def document
    @_document ||= Loofah.html5_fragment(newsletter.body_html.to_s)
  end

  # Leaves alone the paths this app already serves — which is what
  # Newsletter::InlineImages rewrote the cid: references into — and images
  # the message embedded as data URIs.
  def remote?(source)
    source.start_with?("http://", "https://")
  end

  # One pass over the body, as in Newsletter::InlineImages: a gsub per image
  # would copy the whole markup again each time.
  def rewritten_html
    newsletter.body_html.gsub(Regexp.union(replacements.keys)) do |found|
      replacements.fetch(found)
    end
  end

  # Longest first, so a URL that is a prefix of another cannot claim its
  # match — alternation takes the first branch that fits, not the best one.
  def replacements
    @_replacements ||= stored
      .flat_map { |url, blob| spellings(url, newsletter.inline_image_path(blob)) }
      .sort_by { |spelling, _path| -spelling.length }
      .to_h
  end

  # Nokogiri answers a decoded attribute; the body holds what the sender
  # wrote. CDN URLs carry query strings, so an escaped ampersand is the
  # ordinary case rather than the exotic one.
  def spellings(url, path)
    [ [ url, path ], [ CGI.escapeHTML(url), path ] ]
  end
end
