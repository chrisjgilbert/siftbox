require "rails_helper"

RSpec.describe Blog::FeedLink do
  def page(head)
    <<~HTML
      <!DOCTYPE html>
      <html><head><title>Query Plan Weekly</title>#{head}</head>
      <body><p>Notes on databases.</p></body></html>
    HTML
  end

  def found_in(head, at: "https://queryplanweekly.dev/")
    Blog::FeedLink.new(page(head), at).url
  end

  it "finds an RSS feed a page announces" do
    head = %(<link rel="alternate" type="application/rss+xml" href="https://queryplanweekly.dev/feed">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end

  it "finds an Atom feed a page announces" do
    head = %(<link rel="alternate" type="application/atom+xml" href="https://queryplanweekly.dev/atom.xml">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/atom.xml")
  end

  it "finds an RDF feed, which is how RSS 1.0 announces itself" do
    head = %(<link rel="alternate" type="application/rdf+xml" href="https://queryplanweekly.dev/rdf">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/rdf")
  end

  # Most pages write a path rather than a whole address, and it means nothing
  # without the page it was found on.
  it "resolves a relative address against the page it was found on" do
    head = %(<link rel="alternate" type="application/rss+xml" href="/feed.xml">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed.xml")
  end

  it "resolves an address relative to a path deeper than the root" do
    head = %(<link rel="alternate" type="application/rss+xml" href="feed.xml">)

    found = found_in(head, at: "https://queryplanweekly.dev/blog/")

    expect(found).to eq("https://queryplanweekly.dev/blog/feed.xml")
  end

  # WordPress announces the post feed and then the comments feed, in that
  # order, and the reader meant the first one.
  it "takes the first feed a page announces" do
    head = <<~HEAD
      <link rel="alternate" type="application/rss+xml" title="Feed" href="https://queryplanweekly.dev/feed">
      <link rel="alternate" type="application/rss+xml" title="Comments Feed" href="https://queryplanweekly.dev/comments/feed">
    HEAD

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end

  it "ignores an alternate link that is not a feed" do
    head = %(<link rel="alternate" hreflang="fr" href="https://queryplanweekly.dev/fr/">)

    expect(found_in(head)).to be_nil
  end

  it "ignores a stylesheet, which is also a link" do
    head = %(<link rel="stylesheet" href="https://queryplanweekly.dev/app.css">)

    expect(found_in(head)).to be_nil
  end

  it "finds nothing on a page that announces no feed" do
    expect(found_in("")).to be_nil
  end

  # The address is written by the same stranger the feed is, so it gets the
  # same treatment: whatever comes back is fetched next, and Download's own
  # refusals are not the only thing that should be standing in the way.
  it "refuses a feed address that is not one a fetch could follow" do
    head = %(<link rel="alternate" type="application/rss+xml" href="javascript:alert(1)">)

    expect(found_in(head)).to be_nil
  end

  it "refuses a file address a page announces" do
    head = %(<link rel="alternate" type="application/rss+xml" href="file:///etc/passwd">)

    expect(found_in(head)).to be_nil
  end

  it "finds nothing in a document that is not markup at all" do
    expect(Blog::FeedLink.new("", "https://queryplanweekly.dev/").url).to be_nil
  end

  # HTML link relations are ASCII case-insensitive. The type was already
  # folded and the rel was not, so a page written this way announced a feed
  # the app refused to see and the reader was told it was not a feed.
  it "finds a feed announced with a capitalised rel" do
    head = %(<link rel="Alternate" type="application/rss+xml" href="https://queryplanweekly.dev/feed">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end

  it "finds a feed announced with a capitalised type" do
    head = %(<link rel="alternate" type="application/RSS+XML" href="https://queryplanweekly.dev/feed">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end

  # A type may carry parameters, and plenty of generators write one.
  it "finds a feed whose type carries a charset" do
    head = %(<link rel="alternate" type="application/rss+xml; charset=utf-8" href="https://queryplanweekly.dev/feed">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end

  it "still finds a feed announced with rel listing more than alternate" do
    head = %(<link rel="alternate feed" type="application/rss+xml" href="https://queryplanweekly.dev/feed">)

    expect(found_in(head)).to eq("https://queryplanweekly.dev/feed")
  end
end
