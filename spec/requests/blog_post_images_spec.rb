require "rails_helper"

RSpec.describe "Blog post images" do
  def post_with_image(content_type: "image/png")
    post = create(:blog_post)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("not-really-a-png"),
      filename: "figure.png",
      content_type: content_type
    )
    post.inline_images.attach(blob)
    [ post, blob ]
  end

  it "serves a stored image to a signed-in reader" do
    sign_in
    post, blob = post_with_image

    get blog_post_image_path(post, blob)

    expect(response.body).to eq("not-really-a-png")
  end

  it "serves it with the stored content type" do
    sign_in
    post, blob = post_with_image

    get blog_post_image_path(post, blob)

    expect(response.media_type).to eq("image/png")
  end

  # Active Storage's own blob routes never expire and sit outside the
  # authentication gate, which is why these are served here instead.
  it "keeps a signed-out visitor away from a stored image" do
    post, blob = post_with_image

    get blog_post_image_path(post, blob)

    expect(response).to redirect_to(new_session_path)
  end

  it "refuses an image belonging to another post" do
    sign_in
    _post, blob = post_with_image
    other = create(:blog_post)

    get blog_post_image_path(other, blob)

    expect(response).to have_http_status(:not_found)
  end

  # The content type is the publisher's claim. Serving markup inline from
  # this app's own origin would hand them the origin.
  it "refuses to serve a part the publisher labelled as markup" do
    sign_in
    post, blob = post_with_image(content_type: "text/html")

    get blog_post_image_path(post, blob)

    expect(response).to have_http_status(:not_found)
  end

  it "refuses to serve an SVG inline, which can carry script" do
    sign_in
    post, blob = post_with_image(content_type: "image/svg+xml")

    get blog_post_image_path(post, blob)

    expect(response).to have_http_status(:not_found)
  end
end
