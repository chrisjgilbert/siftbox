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

  def initialize(newsletter, parts)
    @newsletter = newsletter
    @parts = parts.select { |part| part.content_id.present? }
  end

  def attach
    return if parts.empty?

    blobs = parts.map { |part| upload(part) }
    newsletter.inline_images.attach(*blobs)
    newsletter.update!(body_html: rewritten_html(blobs))
  end

  private

  attr_reader :newsletter, :parts

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
  def rewritten_html(blobs)
    paths = parts.zip(blobs)
      .to_h { |part, blob| [ "cid:#{part.cid}", newsletter.inline_image_path(blob) ] }

    newsletter.body_html.gsub(Regexp.union(paths.keys)) { |found| paths.fetch(found) }
  end
end
