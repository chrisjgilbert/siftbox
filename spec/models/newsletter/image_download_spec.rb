require "rails_helper"

RSpec.describe Newsletter::ImageDownload do
  # 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
  # accidentally connect, yet unmistakably public to the range checks here.
  def public_resolver
    ->(_host) { [ "203.0.113.9" ] }
  end

  def stub_image(url, bytes: "png-bytes", content_type: "image/png")
    stub_request(:get, url)
      .to_return(body: bytes, headers: { "Content-Type" => content_type })
  end

  def stub_redirect(from, to)
    stub_request(:get, from)
      .to_return(status: 302, headers: { "Location" => to })
  end

  def image_from(url, resolver: public_resolver)
    Newsletter::ImageDownload.new(url, resolver: resolver).image
  end

  it "downloads an image and reports the sender's content type" do
    stub_image("https://cdn.example.com/hero.png")

    image = image_from("https://cdn.example.com/hero.png")

    expect(image).to have_attributes(
      bytes: "png-bytes", content_type: "image/png"
    )
  end

  it "refuses a URL that is not http or https" do
    image = image_from("ftp://cdn.example.com/hero.png")

    expect(image).to be_nil
  end

  # The URL arrives in hostile email HTML and is fetched from inside the
  # network — the textbook server-side request forgery target. No loopback,
  # private, or link-local address may ever be fetched, whatever hostname the
  # sender hides it behind. The resolver is injected because the check has to
  # run on what the name resolves to, not on how it is spelled.
  it "refuses a host that resolves to a loopback address" do
    resolver = ->(_host) { [ "127.0.0.1" ] }

    image = image_from("https://cdn.example.com/hero.png", resolver: resolver)

    expect(image).to be_nil
  end

  it "refuses a host that resolves to a private address" do
    resolver = ->(_host) { [ "10.0.0.5" ] }

    image = image_from("https://cdn.example.com/hero.png", resolver: resolver)

    expect(image).to be_nil
  end

  it "refuses a host that resolves to the cloud metadata address" do
    resolver = ->(_host) { [ "169.254.169.254" ] }

    image = image_from("https://cdn.example.com/hero.png", resolver: resolver)

    expect(image).to be_nil
  end

  it "follows a redirect to another public host" do
    stub_redirect(
      "https://cdn.example.com/hero.png",
      "https://images.example.com/hero.png"
    )
    stub_image("https://images.example.com/hero.png")

    image = image_from("https://cdn.example.com/hero.png")

    expect(image.bytes).to eq("png-bytes")
  end

  # An innocent-looking public URL can answer 302 Location: somewhere
  # internal, so every hop gets the same checks as the first.
  it "refuses a redirect to a host that resolves to a private address" do
    stub_redirect(
      "https://cdn.example.com/hero.png",
      "https://internal.example.com/hero.png"
    )
    resolver = lambda do |host|
      { "cdn.example.com" => [ "203.0.113.9" ] }.fetch(host, [ "10.0.0.5" ])
    end

    image = image_from("https://cdn.example.com/hero.png", resolver: resolver)

    expect(image).to be_nil
  end

  it "gives up after too many redirects" do
    (Newsletter::ImageDownload::MAX_REDIRECTS + 1).times do |hop|
      stub_redirect(
        "https://cdn.example.com/hop-#{hop}.png",
        "https://cdn.example.com/hop-#{hop + 1}.png"
      )
    end

    image = image_from("https://cdn.example.com/hop-0.png")

    expect(image).to be_nil
  end

  it "refuses a response larger than the size cap" do
    stub_image(
      "https://cdn.example.com/huge.png",
      bytes: "x" * (Newsletter::ImageDownload::MAX_BYTES + 1)
    )

    image = image_from("https://cdn.example.com/huge.png")

    expect(image).to be_nil
  end

  it "refuses a response that is not an image" do
    stub_image(
      "https://cdn.example.com/gone.png",
      bytes: "<html>404</html>", content_type: "text/html"
    )

    image = image_from("https://cdn.example.com/gone.png")

    expect(image).to be_nil
  end

  # Same stance as Newsletter::InlineImages::DISPLAYABLE_TYPES: SVG can carry
  # script, so it is never stored however the sender labels it.
  it "refuses an image type the reader never renders" do
    stub_image(
      "https://cdn.example.com/logo.svg",
      bytes: "<svg/>", content_type: "image/svg+xml"
    )

    image = image_from("https://cdn.example.com/logo.svg")

    expect(image).to be_nil
  end

  it "returns nothing when the request times out" do
    stub_request(:get, "https://cdn.example.com/slow.png").to_timeout

    image = image_from("https://cdn.example.com/slow.png")

    expect(image).to be_nil
  end

  it "returns nothing when the connection is refused" do
    stub_request(:get, "https://cdn.example.com/dead.png")
      .to_raise(Errno::ECONNREFUSED)

    image = image_from("https://cdn.example.com/dead.png")

    expect(image).to be_nil
  end
end
