require "rss"

# One fetched feed document, read as posts.
class Blog::Feed
  Item = Data.define(:title)

  def initialize(document)
    @document = document
  end

  def posts
    parsed.items.map { |item| Item.new(title: item.title) }
  end

  private

  attr_reader :document

  def parsed
    @_parsed ||= RSS::Parser.parse(document)
  end
end
