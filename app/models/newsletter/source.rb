# The sender's HTML as it arrived, for the sandboxed "view original" frame.
#
# Images the newsletter carried inside the message are embedded as data URIs
# rather than left pointing at Newsletters::ImagesController. That controller
# authenticates, and the frame is sandboxed without allow-same-origin, so it
# has an opaque origin and sends no session cookie — every inline image would
# 302 to the sign-in page and render broken.
#
# Embedding keeps the sandbox as tight as it is. Loosening it instead would
# mean granting allow-same-origin to the one surface in the app that renders
# sender markup unsanitized.
class Newsletter::Source
  def initialize(newsletter)
    @newsletter = newsletter
  end

  # One pass over the body. A gsub per image would copy the whole markup
  # again each time, over a string already grown by every data URI before it.
  #
  # Encoded inside the block rather than up front, so only the image being
  # substituted is held alongside the result. Building every data URI first
  # meant two copies of the whole payload at once — the hash and the string
  # growing from it — and base64 is already four bytes for every three. A
  # body referencing one blob twice reads it twice; that is a small image
  # read again, against holding every image in the newsletter at once.
  #
  # Longest path first: alternation is leftmost-first, so ".../images/7" ahead
  # of ".../images/71" matches inside it and appends the leftover "1" to the
  # previous image's base64 — two broken images from one collision.
  def html
    return newsletter.body_html if embeddable.empty?

    newsletter.body_html.gsub(longest_first(embeddable.keys)) do |found|
      data_uri(embeddable.fetch(found))
    end
  end

  private

  attr_reader :newsletter

  def longest_first(paths)
    Regexp.union(paths.sort_by { |path| -path.length })
  end

  # Blobs rather than the URIs built from them: an ActiveStorage::Blob is a
  # row, and the bytes stay on disk until #html asks for them.
  #
  # Same allowlist the serving controller applies. A part this app will not
  # render there should not be embedded here either.
  def embeddable
    @_embeddable ||= newsletter.inline_images.blobs
      .select { |blob| Newsletter::InlineImages.displayable?(blob) }
      .index_by { |blob| newsletter.inline_image_path(blob) }
  end

  def data_uri(blob)
    "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
  end
end
