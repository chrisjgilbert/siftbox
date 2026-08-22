require "rails_helper"

RSpec.describe Newsletter::ImageDownload do
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

  # How many connections stand open at once while the block runs. #get
  # returns from inside the request block, so the tally only comes back down
  # in an ensure.
  def peak_open_connections
    open = 0
    peak = 0
    allow(Net::HTTP).to receive(:start).and_wrap_original do |start, *arguments, **options, &block|
      start.call(*arguments, **options) do |http|
        open += 1
        peak = [ peak, open ].max
        begin
          block.call(http)
        ensure
          open -= 1
        end
      end
    end

    yield
    peak
  end

  it "downloads an image and reports the sender's content type" do
    stub_image("https://cdn.example.com/hero.png")

    image = image_from("https://cdn.example.com/hero.png")

    expect(image).to have_attributes(
      bytes: "png-bytes", content_type: "image/png"
    )
  end

  # Which addresses are refused is Destination's own spec. This is the one
  # case kept here, so that removing the check from the fetch fails a spec
  # rather than passing quietly on the strength of the other file.
  it "fetches nothing when the destination refuses the host" do
    resolver = ->(_host) { [ "10.0.0.5" ] }

    image = image_from("https://cdn.example.com/hero.png", resolver: resolver)

    expect(image).to be_nil
  end

  # Net::HTTP resolves the host itself, so passing it the name would mean a
  # second lookup — and a record on a short TTL can answer differently the
  # second time, after every check above has passed. Pinning the address
  # that was checked closes that window. Asserted at the seam because the
  # lookup Net::HTTP would make happens below anything a spec can observe.
  it "connects to the address it checked rather than resolving a second time" do
    stub_image("https://cdn.example.com/hero.png")
    allow(Net::HTTP).to receive(:start).and_call_original

    image_from("https://cdn.example.com/hero.png")

    expect(Net::HTTP).to have_received(:start)
      .with("cdn.example.com", 443, hash_including(ipaddr: "203.0.113.9"))
  end

  # The name still has to reach Net::HTTP, or SNI, certificate verification
  # and the Host header all end up pointed at a bare address — which is what
  # rewriting the URL to the address instead of pinning would have done.
  it "keeps the hostname as the address Net::HTTP verifies against" do
    stub_image("https://cdn.example.com/hero.png")
    allow(Net::HTTP).to receive(:start).and_call_original

    image_from("https://cdn.example.com/hero.png")

    expect(Net::HTTP).to have_received(:start).with("cdn.example.com", anything, anything)
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
    (Download::MAX_REDIRECTS + 1).times do |hop|
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

  # Net::HTTP asks for gzip on every request and inflates the body itself, so
  # a sender who serves a Content-Encoding it then contradicts raises from
  # inside #read_body. Uncaught, that takes down the whole job — and with it
  # every image on the newsletter after this one, not just this one.
  it "returns nothing when the response body will not decompress" do
    stub_request(:get, "https://cdn.example.com/bomb.png")
      .to_raise(Zlib::DataError)

    image = image_from("https://cdn.example.com/bomb.png")

    expect(image).to be_nil
  end

  # The redirect is answered from the hop that reported it, not from inside
  # its still-open connection: a chain otherwise holds one socket per hop
  # open at once, each with a body nothing ever reads.
  it "closes each hop before dialling the next" do
    stub_redirect(
      "https://cdn.example.com/hero.png",
      "https://images.example.com/hero.png"
    )
    stub_image("https://images.example.com/hero.png")

    peak = peak_open_connections { image_from("https://cdn.example.com/hero.png") }

    expect(peak).to eq(1)
  end

  # Nothing here sends a validator, so a 304 is a server answering a question
  # it was not asked. It still has to come back as "no image" rather than as
  # the not-modified marker, which the caller would try to read bytes off.
  it "reports no image when a host answers that nothing has changed" do
    stub_request(:get, "https://cdn.example.com/hero.png").to_return(status: 304)

    image = image_from("https://cdn.example.com/hero.png")

    expect(image).to be_nil
  end
end
