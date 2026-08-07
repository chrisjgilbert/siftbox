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
  def html
    return newsletter.body_html if embedded.empty?

    newsletter.body_html.gsub(Regexp.union(embedded.keys)) { |found| embedded.fetch(found) }
  end

  private

  attr_reader :newsletter

  # Same allowlist the serving controller applies. A part this app will not
  # render there should not be embedded here either.
  def embedded
    @_embedded ||= newsletter.inline_images.blobs
      .select { |blob| Newsletter::InlineImages.displayable?(blob) }
      .to_h { |blob| [ newsletter.inline_image_path(blob), data_uri(blob) ] }
  end

  def data_uri(blob)
    "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
  end
end
