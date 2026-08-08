# Images a newsletter carries inside the message rather than linking to.
#
# Hotlinking cannot render these — a `cid:` reference means nothing to a
# browser — so they are stored and the references rewritten at ingest, while
# the raw email still exists. Action Mailbox incinerates it after 30 days.
class Newsletter::InlineImages
  # The content type is the sender's claim. Rendering whatever they claim,
  # inline and same-origin, would hand them the app's origin — so only raster
  # images, and never SVG, which can carry script. A property of the stored
  # blob, so both the controller that serves it and Newsletter::Source ask
  # the same question.
  DISPLAYABLE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  def self.displayable?(blob)
    DISPLAYABLE_TYPES.include?(blob.content_type)
  end

  # Deduplicated on Content-ID: two parts declaring the same one is malformed
  # but it happens, and it has to be settled before the parts are uploaded.
  # A duplicate key collapses in the rewrite map, so the extra blob would be
  # stored, attached, and referenced by nothing.
  def initialize(newsletter, parts)
    @newsletter = newsletter
    @parts = parts.select { |part| inline_image?(part) }.uniq(&:cid)
  end

  def attach
    return if parts.empty?

    blobs = parts.map { |part| upload(part) }
    newsletter.inline_images.attach(*blobs)
    newsletter.update!(body_html: rewritten_html(blobs))
  end

  private

  attr_reader :newsletter, :parts

  # The same allowlist the serving controller and Newsletter::Source apply.
  # Rewriting a cid: reference for a part this app will never serve turns a
  # missing image into a permanently broken one: the path 404s, and if it is
  # the first image it is stored as lead_image_url and breaks the feed row
  # too. Left as cid:, Newsletter::LeadImage passes over it and the row falls
  # back to "No image in email", which is the truth.
  def inline_image?(part)
    part.content_id.present? &&
      DISPLAYABLE_TYPES.include?(part.mime_type) &&
      readable?(part)
  end

  # Mail raises rather than returning anything for a Content-Transfer-Encoding
  # it does not recognise, and raising here loses the whole newsletter — text,
  # subject, and all — the way Newsletter::InboundMessage's own readers used
  # to. The first question is the one Mail::Body#decoded asks before it raises.
  #
  # The second is whether it decoded to anything. Mail recognises x-uuencode
  # and hands back "" for a part that is not actually uuencoded, so the guard
  # would pass it and a 0-byte blob would be stored, attached, rewritten into
  # the body and promoted to lead_image_url.
  #
  # Skipped rather than stored from the raw source, which is what the body
  # reader does with the same header. Prose survives being read as it stands;
  # an image part almost certainly does not, and a blob of undecoded base64
  # served as an image is broken in the reader and can win lead_image_url and
  # break the feed row too. One missing image beats one lost newsletter, and
  # beats one image that is quietly wrong everywhere it appears.
  #
  # Decodes a second time in #upload rather than carrying the bytes through.
  # A newsletter carries a handful of small inline images, and threading them
  # from here to there costs more reading than the decode does running.
  def readable?(part)
    Mail::Encodings.defined?(part.body.encoding) && part.body.decoded.present?
  end

  def upload(part)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(part.body.decoded),
      filename: filename_for(part),
      content_type: part.mime_type
    )
  end

  # Mail only reports a filename when the part declares one. A multipart
  # related image referenced solely by Content-ID often declares none, and
  # Active Storage will not accept a blank filename.
  def filename_for(part)
    return part.filename if part.filename.present?

    "#{part.cid.to_s.parameterize.presence || 'inline'}.#{extension_for(part)}"
  end

  # Mime::Type knows the structured subtypes that splitting on "/" gets
  # wrong — image/svg+xml is "svg", not "svg+xml".
  def extension_for(part)
    Mime::Type.lookup(part.mime_type.to_s)&.symbol || "bin"
  end

  # One pass over the body rather than one full copy per image.
  #
  # Longest key first: alternation is leftmost-first, so with "cid:logo" ahead
  # of "cid:logo2" the shorter one matches inside the longer and leaves the
  # tail behind — rewriting `cid:logo2` to the wrong blob's path with a stray
  # "2" on the end, which then 404s forever.
  def rewritten_html(blobs)
    paths = paths_for(blobs)

    newsletter.body_html.gsub(longest_first(paths.keys)) { |found| paths.fetch(found) }
  end

  def paths_for(blobs)
    parts.zip(blobs).each_with_object({}) do |(part, blob), found|
      references(part).each { |reference| found[reference] = newsletter.inline_image_path(blob) }
    end
  end

  # Both spellings of the reference. `Mail::Message#cid` URI-escapes the
  # Content-ID — `<a b@x>` reads back as `a%20b@x` — but the sender's src
  # carries what they wrote, so keying on cid alone misses every Content-ID
  # with a character worth escaping in it. The blob is stored either way, so
  # the miss leaves an image on disk that no page can render.
  def references(part)
    [ "cid:#{part.cid}", "cid:#{unbracketed(part)}" ].uniq
  end

  def unbracketed(part)
    part.content_id.to_s.delete_prefix("<").delete_suffix(">")
  end

  def longest_first(keys)
    Regexp.union(keys.sort_by { |key| -key.length })
  end
end
