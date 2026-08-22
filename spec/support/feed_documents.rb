# The channel furniture an RSS 2.0 document needs, so that four spec files do
# not each carry their own copy of it.
#
# Only the wrapper is shared. What each example is actually about — the items,
# their fields, and what is missing from them — stays in the example, because
# that is the part a reader has to see to know what is being asserted.
#
# The content and dc namespaces are declared whether or not a given example
# uses them: an undeclared prefix is a parse error, and declaring one that
# goes unused costs nothing.
module FeedDocuments
  def rss_document(items = "")
    <<~XML
      <?xml version="1.0"?>
      <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel>
          <title>Query Plan Weekly</title>
          <link>https://queryplanweekly.dev</link>
          <description>Notes on databases</description>
      #{items}
        </channel>
      </rss>
    XML
  end

  # An item carrying a real article, which is what Blog::Subscription admits
  # and Blog::Post::EDITORIAL_MINIMUM clears. For specs where an accepted feed
  # is furniture rather than the assertion — where the body's length IS the
  # assertion, write it out in the example.
  def rss_article(title)
    <<~XML
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>#{"word " * 200}</description>
      </item>
    XML
  end

  # A blog's home page, announcing where its feed is.
  def home_page(feed_url)
    <<~HTML
      <!DOCTYPE html>
      <html><head><title>Query Plan Weekly</title>
      <link rel="alternate" type="application/rss+xml" href="#{feed_url}"></head>
      <body><p>Notes on databases.</p></body></html>
    HTML
  end

  # One item with a guid derived from its title, which is what a poll dedupes
  # on. Enough for any example whose subject is the polling rather than the
  # parsing.
  def rss_item(title)
    <<~XML
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>#{title}, at length.</description>
      </item>
    XML
  end
end

RSpec.configure do |config|
  config.include FeedDocuments
end
