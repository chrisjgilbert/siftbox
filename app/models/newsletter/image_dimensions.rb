# The sizes of the images this app stores for a newsletter, keyed by the path
# body_html points at.
#
# Read at render rather than written into body_html at ingest, so the archive
# gains them as soon as Active Storage has analysed a blob and nothing has to
# be reprocessed — the same reason sanitizing happens at render. See
# Newsletter::Body.
#
# Without them the browser cannot reserve space for an image before it loads,
# so every image in a newsletter shifts the text the reader is already
# looking at.
class Newsletter::ImageDimensions
  def initialize(newsletter)
    @newsletter = newsletter
  end

  def to_h
    @_to_h ||= newsletter.inline_images.blobs.each_with_object({}) do |blob, sizes|
      width, height = blob.metadata.values_at("width", "height")
      next if width.blank? || height.blank?

      sizes[newsletter.inline_image_path(blob)] = [ width, height ]
    end
  end

  private

  attr_reader :newsletter
end
