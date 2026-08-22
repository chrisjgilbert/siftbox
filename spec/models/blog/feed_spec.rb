require "rails_helper"

RSpec.describe Blog::Feed do
  # An RSS 2.0 channel carrying whatever items the example needs. The channel
  # furniture is required by the format and says nothing the parser is being
  # asked about, so it lives here rather than in every example.
  def rss_document(items)
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0">
        <channel>
          <title>Query Plan Weekly</title>
          <link>https://queryplanweekly.dev</link>
          <description>Notes on databases</description>
      #{items}
        </channel>
      </rss>
    XML
  end

  it "reads one post per item in an RSS document" do
    document = rss_document(<<~ITEMS)
      <item><title>Why your index is not being used</title></item>
      <item><title>Counting rows is harder than it looks</title></item>
    ITEMS

    feed = Blog::Feed.new(document)

    expect(feed.posts.map(&:title))
      .to eq([ "Why your index is not being used", "Counting rows is harder than it looks" ])
  end
end
