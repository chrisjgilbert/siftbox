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
    # Built by the app, not hand-written, so this fails if the two ever
    # disagree about the path rather than silently testing a literal.
    path = newsletter.inline_image_path(blob)
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

  # Regexp.union alternates in the order it is given and Ruby matches
  # leftmost-first, not longest. A blob id that prefixes another matched
  # inside it, embedding the wrong bytes and leaving the tail on the end of
  # the base64.
  it "embeds each image when one blob id is a prefix of another" do
    newsletter = create(:newsletter)
    blobs = %w[one two].map do |name|
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(name), filename: "#{name}.png", content_type: "image/png"
      )
    end
    newsletter.inline_images.attach(*blobs)
    paths = blobs.map { |blob| newsletter.inline_image_path(blob) }
    newsletter.update!(body_html: paths.map { |path| %(<img src="#{path}">) }.join)

    result = Newsletter::Source.new(newsletter).html

    expect(result).to include(Base64.strict_encode64("one"))
      .and include(Base64.strict_encode64("two"))
  end

  # A logo in the header and again in the footer is one blob and two
  # references. #html encodes on demand rather than up front, so this is the
  # one shape that reads the same blob twice.
  it "embeds an image the body references twice at both references" do
    newsletter = newsletter_with_inline_image
    path = newsletter.inline_images.blobs.first.then { |blob| newsletter.inline_image_path(blob) }
    newsletter.update!(body_html: %(<img src="#{path}"><p>Hi</p><img src="#{path}">))

    result = Newsletter::Source.new(newsletter).html

    expect(result.scan("data:image/png;base64,#{Base64.strict_encode64('pretend-png-bytes')}").length)
      .to eq(2)
  end

  it "leaves no path behind when one blob id is a prefix of another" do
    newsletter = create(:newsletter)
    blobs = %w[one two].map do |name|
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(name), filename: "#{name}.png", content_type: "image/png"
      )
    end
    newsletter.inline_images.attach(*blobs)
    paths = blobs.map { |blob| newsletter.inline_image_path(blob) }
    newsletter.update!(body_html: paths.map { |path| %(<img src="#{path}">) }.join)

    expect(Newsletter::Source.new(newsletter).html).not_to include("/images/")
  end
end
