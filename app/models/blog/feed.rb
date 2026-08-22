require "rss"

# One fetched feed document, read as posts.
class Blog::Feed
  Item = Data.define(:title, :url, :body_html, :published_at)

  def initialize(document)
    @document = document
  end

  def posts
    parsed.items.map do |item|
      Item.new(
        title: item.title, url: item.link, body_html: body_of(item),
        published_at: item.pubDate
      )
    end
  end

  private

  attr_reader :document

  # content:encoded is where a blog publishing full text puts the article, and
  # description is then a summary of it. Preferring the shorter one would hand
  # the editor a blurb and let it report the post as a stub.
  def body_of(item)
    item.content_encoded.presence || item.description
  end

  def parsed
    @_parsed ||= RSS::Parser.parse(document)
  end
end
