require "rails_helper"

RSpec.describe Newsletter::RemoteImages do
  # Stands in for Newsletter::ImageDownload, which owns the wire protocol.
  # These specs cover everything around it: which srcs get fetched, what is
  # stored, and how the body is rewritten.
  def download_answering(images, seen: [])
    lambda do |url|
      seen << url
      images[url]
    end
  end

  def stored_image
    Data.define(:bytes, :content_type)
      .new(bytes: "png-bytes", content_type: "image/png")
  end

  def newsletter_with(body_html)
    create(:newsletter, body_html: body_html)
  end

  it "stores a hotlinked image on the newsletter" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/a.png">))
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.inline_images).to be_attached
  end

  it "rewrites the src to a path this app serves" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/a.png">))
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html)
      .to include("/newsletters/#{newsletter.id}/images/")
  end

  it "leaves no reference to the sender's image host behind" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/a.png">))
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html).not_to include("cdn.example.com")
  end

  it "downloads an image the body repeats only once" do
    seen = []
    newsletter = newsletter_with(
      %(<img src="https://cdn.example.com/a.png">) * 2
    )
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }, seen: seen
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(seen).to eq([ "https://cdn.example.com/a.png" ])
  end

  it "rewrites every occurrence of a repeated image" do
    newsletter = newsletter_with(
      %(<img src="https://cdn.example.com/a.png">) * 2
    )
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    served = newsletter.reload.body_html
      .scan("/newsletters/#{newsletter.id}/images/")
    expect(served.length).to eq(2)
  end

  # The parser answers a decoded src, the body holds what the sender wrote,
  # and CDN URLs carry query strings — so the two disagree on most real
  # newsletters, and a rewrite keyed on the decoded form finds nothing.
  it "rewrites a source the sender wrote with an escaped ampersand" do
    newsletter = newsletter_with(
      %(<img src="https://cdn.example.com/a.png?w=1&amp;h=2">)
    )
    download = download_answering(
      { "https://cdn.example.com/a.png?w=1&h=2" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html).not_to include("cdn.example.com")
  end

  # Alternation takes the first branch that fits, so without the longest
  # spelling first the bare URL matches inside the longer one and leaves its
  # query string dangling off the end of the rewritten path.
  it "replaces the whole of a source another source is a prefix of" do
    newsletter = newsletter_with(
      %(<img src="https://cdn.example.com/a.png">) +
      %(<img src="https://cdn.example.com/a.png?size=2">)
    )
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image,
        "https://cdn.example.com/a.png?size=2" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html).not_to include("?size=2")
  end

  it "names the blob after the file the URL ends in" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/hero.png">))
    download = download_answering(
      { "https://cdn.example.com/hero.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.inline_images.blobs.first.filename.to_s).to eq("hero.png")
  end

  # Plenty of CDN URLs end in an opaque path segment, and Active Storage
  # will not accept a blank filename.
  it "names a blob after its type when the URL ends in no file" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/render/9f2">))
    download = download_answering(
      { "https://cdn.example.com/render/9f2" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.inline_images.blobs.first.filename.to_s).to eq("image.png")
  end

  it "leaves the src alone when the download comes back empty" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/a.png">))
    download = download_answering({})

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html)
      .to include("https://cdn.example.com/a.png")
  end

  it "attaches nothing when the download comes back empty" do
    newsletter = newsletter_with(%(<img src="https://cdn.example.com/a.png">))
    download = download_answering({})

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.inline_images).not_to be_attached
  end

  # One dead host must not cost the reader the images that did arrive.
  it "keeps what it can when only some downloads succeed" do
    newsletter = newsletter_with(
      %(<img src="https://cdn.example.com/a.png">) +
      %(<img src="https://cdn.example.com/dead.png">)
    )
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html)
      .to include("/newsletters/#{newsletter.id}/images/")
      .and include("https://cdn.example.com/dead.png")
  end

  # Older newsletter templates still carry these. A browser resolves the
  # scheme from the page, and this app is served over https.
  it "fetches a protocol-relative source over https" do
    seen = []
    newsletter = newsletter_with(%(<img src="//cdn.example.com/a.png">))
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }, seen: seen
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(seen).to eq([ "https://cdn.example.com/a.png" ])
  end

  it "rewrites a protocol-relative source" do
    newsletter = newsletter_with(%(<img src="//cdn.example.com/a.png">))
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html).not_to include("cdn.example.com")
  end

  # A protocol-relative source is the tail of the absolute URL, so an
  # unguarded rewrite reaches inside a link elsewhere in the body and leaves
  # "https:" glued to a path this app serves.
  it "leaves alone an absolute URL the source is only the tail of" do
    newsletter = newsletter_with(
      %(<a href="https://cdn.example.com/a.png">) +
      %(<img src="//cdn.example.com/a.png"></a>)
    )
    download = download_answering(
      { "https://cdn.example.com/a.png" => stored_image }
    )

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html)
      .to include(%(href="https://cdn.example.com/a.png"))
  end

  it "fetches nothing for an image this app already serves" do
    seen = []
    newsletter = newsletter_with(%(<img src="/newsletters/1/images/2">))
    download = download_answering({}, seen: seen)

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(seen).to be_empty
  end

  it "fetches nothing for an image embedded as a data URI" do
    seen = []
    newsletter = newsletter_with(%(<img src="data:image/png;base64,AAAA">))
    download = download_answering({}, seen: seen)

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(seen).to be_empty
  end

  it "leaves a newsletter with no images untouched" do
    newsletter = newsletter_with("<p>Morning</p>")
    download = download_answering({})

    Newsletter::RemoteImages.new(newsletter, download: download).attach

    expect(newsletter.reload.body_html).to eq("<p>Morning</p>")
  end
end
