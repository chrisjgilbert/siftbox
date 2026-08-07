require "rails_helper"

RSpec.describe "Newsletter images" do
  def newsletter_with_image(content_type: "image/png")
    newsletter = create(:newsletter)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("not-really-a-png"),
      filename: "logo.png",
      content_type: content_type
    )
    newsletter.inline_images.attach(blob)
    [ newsletter, blob ]
  end

  it "serves an inline image to a signed-in reader" do
    sign_in
    newsletter, blob = newsletter_with_image

    get newsletter_image_path(newsletter, blob)

    expect(response.body).to eq("not-really-a-png")
  end

  it "serves it with the stored content type" do
    sign_in
    newsletter, blob = newsletter_with_image

    get newsletter_image_path(newsletter, blob)

    expect(response.media_type).to eq("image/png")
  end

  it "keeps a signed-out visitor away from an inline image" do
    newsletter, blob = newsletter_with_image

    get newsletter_image_path(newsletter, blob)

    expect(response).to redirect_to(new_session_path)
  end

  it "refuses an image belonging to another newsletter" do
    sign_in
    _newsletter, blob = newsletter_with_image
    other = create(:newsletter)

    get newsletter_image_path(other, blob)

    expect(response).to have_http_status(:not_found)
  end

  # The content type is the sender's claim. Serving markup inline from the
  # app's own origin would hand them the origin.
  it "refuses to serve a part the sender labelled as markup" do
    sign_in
    newsletter, blob = newsletter_with_image(content_type: "text/html")

    get newsletter_image_path(newsletter, blob)

    expect(response).to have_http_status(:not_found)
  end

  it "refuses to serve an SVG inline, which can carry script" do
    sign_in
    newsletter, blob = newsletter_with_image(content_type: "image/svg+xml")

    get newsletter_image_path(newsletter, blob)

    expect(response).to have_http_status(:not_found)
  end
end
