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
    newsletter.update!(body_html: rewritten_html(blobs))
  end

  private

  attr_reader :newsletter, :parts

  def upload(part)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(part.body.decoded),
      filename: part.filename,
      content_type: part.mime_type
    ).tap { |blob| newsletter.inline_images.attach(blob) }
  end

  def rewritten_html(blobs)
    parts.zip(blobs).reduce(newsletter.body_html) do |html, (part, blob)|
      html.gsub("cid:#{part.cid}", path_for(blob))
    end
  end

  def path_for(blob)
    Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
  end
end
