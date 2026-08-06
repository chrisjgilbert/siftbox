require "rails_helper"

RSpec.describe Newsletter::Source do
  def newsletter_with_inline_image
    newsletter = create(:newsletter)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("pretend-png-bytes"),
      filename: "logo.png",
      content_type: "image/png"
    )
    newsletter.inline_images.attach(blob)
    path = "/newsletters/#{newsletter.id}/images/#{blob.id}"
    newsletter.update!(body_html: %(<p>Hi</p><img src="#{path}">))
    newsletter
  end

  it "embeds an inline image the sandboxed frame could not fetch" do
    newsletter = newsletter_with_inline_image

    expect(Newsletter::Source.new(newsletter).html).to include("data:image/png;base64,")
  end

  it "leaves no path the sandboxed frame would have to authenticate for" do
    newsletter = newsletter_with_inline_image

    expect(Newsletter::Source.new(newsletter).html).not_to include("/images/")
  end

  it "embeds the stored bytes" do
    newsletter = newsletter_with_inline_image

    encoded = Base64.strict_encode64("pretend-png-bytes")

    expect(Newsletter::Source.new(newsletter).html).to include(encoded)
  end

  it "leaves a hotlinked image alone" do
    newsletter = create(:newsletter, body_html: %(<img src="https://cdn.example/a.png">))

    expect(Newsletter::Source.new(newsletter).html).to include("https://cdn.example/a.png")
  end

  it "returns the body unchanged when the newsletter carries no inline images" do
    newsletter = create(:newsletter, body_html: "<p>Morning</p>")

    expect(Newsletter::Source.new(newsletter).html).to eq("<p>Morning</p>")
  end
end
