require "rails_helper"

RSpec.describe Blog::PollJob do
  # The job builds its own fetch, so there is no resolver to inject — and
  # Destination really does look a hostname up, which WebMock does not stub.
  # 203.0.113.9 is TEST-NET-3 (RFC 5737): never routable, so nothing can
  # accidentally connect, yet unmistakably public to the range checks.
  def resolve_publicly
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.9" ])
  end

  def stub_feed(blog, body)
    stub_request(:get, blog.feed_url)
      .to_return(body: body, headers: { "Content-Type" => "application/rss+xml" })
  end

  def one_post(title)
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0"><channel>
      <title>Query Plan Weekly</title><link>https://queryplanweekly.dev</link>
      <description>Notes on databases</description>
      <item><title>#{title}</title><guid>#{title.parameterize}</guid></item>
      </channel></rss>
    XML
  end

  it "polls every blog on the roster" do
    resolve_publicly
    first = create(:blog)
    second = create(:blog)
    stub_feed(first, one_post("From the first"))
    stub_feed(second, one_post("From the second"))

    Blog::PollJob.perform_now

    expect(Blog::Post.pluck(:title))
      .to contain_exactly("From the first", "From the second")
  end

  # One blog answering badly is an ordinary Tuesday, and it must not cost the
  # rest of the roster their poll — which is what an exception escaping here
  # would do, since the job would stop at whichever blog raised.
  it "polls the rest of the roster when one blog raises" do
    resolve_publicly
    broken = create(:blog)
    working = create(:blog)
    stub_request(:get, broken.feed_url).to_raise(SocketError)
    stub_feed(working, one_post("From the working one"))

    Blog::PollJob.perform_now

    expect(Blog::Post.pluck(:title)).to eq([ "From the working one" ])
  end

  it "records a blog that raised as failing" do
    resolve_publicly
    broken = create(:blog, failing_since: nil)
    stub_request(:get, broken.feed_url).to_raise(SocketError)

    Blog::PollJob.perform_now

    expect(broken.reload.failing_since).to be_present
  end
end
