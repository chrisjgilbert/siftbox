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

  def html
    newsletter.inline_images.blobs.reduce(newsletter.body_html) do |markup, blob|
      markup.gsub(path_for(blob), data_uri(blob))
    end
  end

  private

  attr_reader :newsletter

  def path_for(blob)
    Rails.application.routes.url_helpers.newsletter_image_path(newsletter, blob)
  end

  def data_uri(blob)
    "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
  end
end
