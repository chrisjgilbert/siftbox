# A feed served over the wire, for the specs that go through the real fetch
# stack rather than around it.
#
# resolve_publicly plus WebMock rather than stubbing Blog::Subscription's or
# Blog::Poll's constructor: a stubbed constructor is the only place the
# default fetcher gets bound, so it leaves Blog::Fetch and Download untouched
# by every example on that path — which was demonstrated, by breaking the
# production wiring four ways with the suite still green.
#
# Several documents in turn is what following a home page takes: the page
# first, then the feed it announced.
module FeedServing
  def serving(feed_url, *documents)
    resolve_publicly
    stub_request(:get, feed_url).to_return(
      documents.map { |document| answer(document) }
    )
  end

  def stub_feed(blog, document)
    serving(blog.feed_url, document)
  end

  private

  # The type is stated because a real server states one, and because
  # Blog::Fetch deliberately refuses to read anything into it — the header
  # being present and ignored is part of what these examples cover.
  def answer(document)
    { body: document, headers: { "Content-Type" => "application/rss+xml" } }
  end
end

RSpec.configure do |config|
  config.include FeedServing
end
