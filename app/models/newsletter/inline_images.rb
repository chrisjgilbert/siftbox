# Images a newsletter carries inside the message rather than linking to.
#
# Hotlinking cannot render these — a `cid:` reference means nothing to a
# browser — so they are stored and the references rewritten at ingest, while
# the raw email still exists. Action Mailbox incinerates it after 30 days.
class Newsletter::InlineImages
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

  def extension_for(part)
    part.mime_type.to_s.split("/").last.presence || "bin"
  end

  # One pass over the body rather than one full copy per image.
  def rewritten_html(blobs)
    paths = parts.zip(blobs).to_h { |part, blob| [ "cid:#{part.cid}", path_for(blob) ] }

    newsletter.body_html.gsub(Regexp.union(paths.keys)) { |found| paths.fetch(found) }
  end

  # The app's own route rather than rails_blob_path: Active Storage's blob
  # routes are not behind the authentication gate. See
  # Newsletters::ImagesController.
  def path_for(blob)
    Rails.application.routes.url_helpers.newsletter_image_path(newsletter, blob)
  end
end
