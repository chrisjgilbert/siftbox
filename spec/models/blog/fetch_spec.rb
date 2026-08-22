require "rails_helper"

RSpec.describe Blog::Fetch do
  # 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
  # accidentally connect, yet unmistakably public to the range checks.
  def public_resolver
    ->(_host) { [ "203.0.113.9" ] }
  end

  def feed_bytes
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0"><channel>
      <title>Query Plan Weekly</title><link>https://queryplanweekly.dev</link>
      <description>Notes on databases</description>
      </channel></rss>
    XML
  end

  def fetched(blog)
    Blog::Fetch.new(blog, resolver: public_resolver).result
  end

  it "answers the document a feed served" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed")
    stub_request(:get, blog.feed_url).to_return(
      body: feed_bytes, headers: { "Content-Type" => "application/rss+xml" }
    )

    expect(fetched(blog).document).to include("Query Plan Weekly")
  end

  # The bytes arrive tagged however Net::HTTP felt about them, and the parser
  # raises outright on a string tagged as an encoding it is not. This is the
  # same problem Newsletter::InboundMessage#utf8 solves for mail, and it is
  # the fetch's to solve here because a feed declares its encoding twice — in
  # the XML declaration and in the HTTP charset — and the two may disagree.
  it "answers a document tagged as UTF-8" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed")
    stub_request(:get, blog.feed_url).to_return(
      body: feed_bytes.dup.force_encoding(Encoding::ASCII_8BIT),
      headers: { "Content-Type" => "application/rss+xml" }
    )

    expect(fetched(blog).document.encoding).to eq(Encoding::UTF_8)
  end

  it "carries back the validators the server sent" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed")
    stub_request(:get, blog.feed_url).to_return(
      body: feed_bytes,
      headers: {
        "Content-Type" => "application/rss+xml", "ETag" => "\"abc\"",
        "Last-Modified" => "Wed, 20 Aug 2026 09:00:00 GMT"
      }
    )

    expect(fetched(blog).etag).to eq("\"abc\"")
  end

  # What makes an hourly poll polite. A feed that has not changed answers 304
  # with no body at all, which costs the publisher a header exchange rather
  # than a megabyte.
  it "sends the validators it was given last time" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed",
      etag: "\"abc\"", last_modified_header: "Wed, 20 Aug 2026 09:00:00 GMT")
    request = stub_request(:get, blog.feed_url)
      .with(headers: {
        "If-None-Match" => "\"abc\"",
        "If-Modified-Since" => "Wed, 20 Aug 2026 09:00:00 GMT"
      })
      .to_return(status: 304)

    fetched(blog)

    expect(request).to have_been_requested
  end

  it "reports a feed that has not changed" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed", etag: "\"abc\"")
    stub_request(:get, blog.feed_url).to_return(status: 304)

    expect(fetched(blog)).to be(Blog::Fetch::UNCHANGED)
  end

  it "reports nothing at all when the fetch fails" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed")
    stub_request(:get, blog.feed_url).to_return(status: 500)

    expect(fetched(blog)).to be_nil
  end

  # Blogs are asked for by a reader rather than by a stranger, but a blog can
  # still redirect — and a redirect to an address inside this network is the
  # same server-side request forgery whoever typed the original URL.
  it "refuses a feed that resolves to a private address" do
    blog = create(:blog, feed_url: "https://queryplanweekly.dev/feed")
    private_resolver = ->(_host) { [ "169.254.169.254" ] }

    result = Blog::Fetch.new(blog, resolver: private_resolver).result

    expect(result).to be_nil
  end
end
