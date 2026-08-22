require "rails_helper"

# The redirect ceiling, the wall clock, the size cap and the refusal to reach
# anywhere private are all exercised through Newsletter::ImageDownload, which
# was this class before it was extracted and whose spec still drives the whole
# of it. What is here is what only became reachable once the caller could
# choose: an allowlist that is off, and a cap that is an argument.
RSpec.describe Download do
  # 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
  # accidentally connect, yet unmistakably public to the range checks.
  def public_resolver
    ->(_host) { [ "203.0.113.9" ] }
  end

  def stub_body(url, bytes:, content_type:)
    stub_request(:get, url)
      .to_return(body: bytes, headers: { "Content-Type" => content_type })
  end

  # A feed is served under half a dozen content types and as many
  # misconfigured spellings besides — text/html and application/octet-stream
  # among them — so the caller that wants one asks for no allowlist at all and
  # lets the parser decide whether what came back is really a feed.
  it "reads any content type when no allowlist is given" do
    stub_body("https://queryplanweekly.dev/feed",
      bytes: "<rss/>", content_type: "text/html")

    body = Download.new("https://queryplanweekly.dev/feed",
      max_bytes: 1.megabyte, resolver: public_resolver).body

    expect(body.bytes).to eq("<rss/>")
  end

  it "refuses a content type outside an allowlist it was given" do
    stub_body("https://cdn.example.com/hero.png",
      bytes: "<html/>", content_type: "text/html")

    body = Download.new("https://cdn.example.com/hero.png",
      max_bytes: 1.megabyte, types: [ "image/png" ], resolver: public_resolver).body

    expect(body).to be_nil
  end

  # The cap is the caller's rather than this class's, because the two callers
  # want different ones: five megabytes is generous for an image and too small
  # for a feed, one of which measured 11.2MB in docs/blogs-rss.md.
  it "refuses a body larger than the cap it was given" do
    stub_body("https://queryplanweekly.dev/feed",
      bytes: "x" * 2_000, content_type: "application/rss+xml")

    body = Download.new("https://queryplanweekly.dev/feed",
      max_bytes: 1_000, resolver: public_resolver).body

    expect(body).to be_nil
  end

  it "reads a body inside the cap it was given" do
    stub_body("https://queryplanweekly.dev/feed",
      bytes: "x" * 2_000, content_type: "application/rss+xml")

    body = Download.new("https://queryplanweekly.dev/feed",
      max_bytes: 1.megabyte, resolver: public_resolver).body

    expect(body.bytes.bytesize).to eq(2_000)
  end
end
