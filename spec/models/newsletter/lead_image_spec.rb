require "rails_helper"

RSpec.describe Newsletter::LeadImage do
  # Takes a Newsletter::Body, so the caller decides what that body knows. The
  # sizes only matter to #remainder, and none of these examples assert on one.
  def lead_image_for(html)
    Newsletter::LeadImage.new(Newsletter::Body.new(html))
  end

  it "takes the first image in the body" do
    html = %(<img src="https://cdn.example/hero.png"><img src="https://cdn.example/two.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the body carries no images" do
    result = lead_image_for("<p>Morning</p>").url

    expect(result).to eq("")
  end

  it "has no url when the body is empty" do
    result = lead_image_for("").url

    expect(result).to eq("")
  end

  # The scrubber runs first, so a beacon is gone before the first image is
  # picked. Without that order every newsletter leads with a 1x1 gif.
  it "passes over a tracking pixel to reach the real image" do
    html = %(<img src="https://track.example/o.gif" width="1"><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the only image is a tracking pixel" do
    html = %(<img src="https://track.example/o.gif" width="1" height="1">)

    result = lead_image_for(html).url

    expect(result).to eq("")
  end

  # A data: URI is usually a spacer or a bullet, and storing one puts
  # kilobytes of base64 into a column the feed reads on every row.
  it "passes over a data uri to reach a hosted image" do
    html = %(<img src="data:image/gif;base64,R0lGOD"><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the only image is a data uri" do
    result = lead_image_for(%(<img src="data:image/gif;base64,R0lGOD">)).url

    expect(result).to eq("")
  end

  it "has no url for an image with no source at all" do
    result = lead_image_for("<img>").url

    expect(result).to eq("")
  end

  # A cid: reference means nothing to a browser. One surviving here is an
  # inline image that failed to attach, not a lead.
  it "passes over an unrewritten cid reference" do
    html = %(<img src="cid:logo@sender"><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  # Newsletter::InlineImages rewrites cid: references to app paths before
  # this runs, so an image carried inside the message is a legitimate lead.
  it "takes an inline image rewritten to an app path" do
    html = %(<img src="/newsletters/1/images/abc">)

    result = lead_image_for(html).url

    expect(result).to eq("/newsletters/1/images/abc")
  end

  it "drops the lead image from the remainder" do
    html = %(<p>Morning</p><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).remainder

    expect(result).not_to include("hero.png")
  end

  it "keeps the rest of the body in the remainder" do
    html = %(<p>Morning</p><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).remainder

    expect(result).to include("<p>Morning</p>")
  end

  it "keeps later images in the remainder" do
    html = %(<img src="https://cdn.example/hero.png"><img src="https://cdn.example/two.png">)

    result = lead_image_for(html).remainder

    expect(result).to include("two.png")
  end

  it "leaves the body alone when there is no lead image to drop" do
    result = lead_image_for("<p>Morning</p>").remainder

    expect(result).to include("<p>Morning</p>")
  end

  # The two readers run in different places — extraction at ingest, the
  # remainder at render — but nothing stops one instance answering both, and
  # a caller should not have to know that #remainder mutates the document.
  it "still knows the url after the remainder has been taken" do
    lead = lead_image_for(%(<img src="https://cdn.example/hero.png">))

    lead.remainder

    expect(lead.url).to eq("https://cdn.example/hero.png")
  end

  # The reader captions the promoted image with whatever the email said about
  # it. Read here rather than stored, because the caption is only ever needed
  # on the page that already has the body open.
  it "carries the lead image's alt text" do
    html = %(<img src="https://cdn.example/hero.png" alt="The new parser">)

    result = lead_image_for(html).alt

    expect(result).to eq("The new parser")
  end

  it "has no alt text when the image declares none" do
    result = lead_image_for(%(<img src="https://cdn.example/hero.png">)).alt

    expect(result).to eq("")
  end

  it "has no alt text when there is no lead image at all" do
    expect(lead_image_for("<p>Morning</p>").alt).to eq("")
  end

  # A sender who writes a relative URL points the reader's own browser back at
  # this app, with the session cookie attached. /newsletters/:id marks a
  # newsletter read on GET, so that reference must never reach a src.
  it "passes over a relative url pointing back at the app" do
    html = %(<img src="/newsletters/5"><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the only image is a relative path" do
    result = lead_image_for(%(<img src="hero.png">)).url

    expect(result).to eq("")
  end

  it "takes a protocol-relative image, which resolves to the sender's host" do
    result = lead_image_for(%(<img src="//cdn.example/hero.png">)).url

    expect(result).to eq("//cdn.example/hero.png")
  end

  # Loofah percent-encodes the padding on its way through, so `src=" https://…"`
  # arrives as "%20https://…" and no browser resolves it either. Refusing it
  # here agrees with what the reader's own body renders.
  it "passes over an image whose source is padded with whitespace" do
    html = %(<img src=" https://cdn.example/padded.png "><img src="https://cdn.example/hero.png">)

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  # Asserted through a parse rather than on the string, because #scrubbed
  # keeps the class attribute a CMS puts on its figures — so a body left
  # holding <figure class="kg-card"> does not contain the substring "<figure>"
  # and a text assertion reads green with the bug in place.
  def figures_in(html)
    Nokogiri::HTML5.fragment(html).css("figure")
  end

  def figure_holding(image, caption: "Where the first 900ms goes")
    %(<p>Before</p><figure>#{image}<figcaption>#{caption}</figcaption></figure><p>After</p>)
  end

  # A <figure> exists to tie an image to its caption. Lifting the image above
  # the article and leaving the figure behind strands the caption mid-body,
  # describing a picture that is no longer beside it.
  it "drops the caption of the figure it took the lead image from" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png">))

    result = lead_image_for(html).remainder

    expect(result).not_to include("Where the first 900ms goes")
  end

  it "leaves no figure standing where the lead image was" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png">))

    result = lead_image_for(html).remainder

    expect(figures_in(result)).to be_empty
  end

  it "keeps the article around the figure it removed" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png">))

    result = lead_image_for(html).remainder

    expect(result).to include("<p>Before</p>").and include("<p>After</p>")
  end

  # What a CMS actually emits: the image wrapped in a link to the full-size
  # version, so the image's own parent is the <a> and not the figure.
  it "takes the figure when the lead image is wrapped in a link" do
    html = figure_holding(
      %(<a href="https://cdn.example/full.png"><img src="https://cdn.example/hero.png"></a>)
    )

    result = lead_image_for(html).remainder

    expect(figures_in(result)).to be_empty
  end

  it "captions a linked lead image from the figure that wraps it" do
    html = figure_holding(
      %(<a href="https://cdn.example/full.png"><img src="https://cdn.example/hero.png"></a>)
    )

    result = lead_image_for(html).caption

    expect(result).to eq("Where the first 900ms goes")
  end

  # The caption travels with the image rather than being dropped alongside it.
  it "captions the promoted image with the figure's caption" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png" alt="A flame graph">))

    result = lead_image_for(html).caption

    expect(result).to eq("Where the first 900ms goes")
  end

  # alt is written for someone who cannot see the picture and the caption for
  # someone who can. The reader has a slot for each, so the caption never
  # overwrites the alt text — a photo credit is no use to a screen reader.
  it "keeps the image's own alt text when the figure carries a caption" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png" alt="A flame graph">))

    result = lead_image_for(html).alt

    expect(result).to eq("A flame graph")
  end

  it "falls back to the alt text when the figure carries no caption" do
    html = %(<figure><img src="https://cdn.example/hero.png" alt="A flame graph"></figure>)

    result = lead_image_for(html).caption

    expect(result).to eq("A flame graph")
  end

  it "has no caption when neither the figure nor the image says anything" do
    result = lead_image_for(%(<figure><img src="https://cdn.example/hero.png"></figure>)).caption

    expect(result).to eq("")
  end

  it "has no caption when there is no lead image at all" do
    expect(lead_image_for("<p>Morning</p>").caption).to eq("")
  end

  # A figure holding prose beside its image is the sender using it as a layout
  # box. Taking it out would delete that sentence from the article — it is not
  # promoted, not captioned, just gone.
  it "keeps a figure holding prose beside the lead image" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png">The sponsor is Acme.))

    result = lead_image_for(html).remainder

    expect(result).to include("The sponsor is Acme.")
  end

  it "keeps a figure holding a block beside the lead image" do
    html = %(<figure><img src="https://cdn.example/hero.png"><p>A whole paragraph</p></figure>)

    result = lead_image_for(html).remainder

    expect(result).to include("A whole paragraph")
  end

  it "still removes the lead image from a figure it leaves standing" do
    html = %(<figure><img src="https://cdn.example/hero.png"><p>A whole paragraph</p></figure>)

    result = lead_image_for(html).remainder

    expect(result).not_to include("hero.png")
  end

  # Removing the figure would take the second image out of the article with it.
  it "keeps a figure holding a second image beside the lead" do
    html = figure_holding(
      %(<img src="https://cdn.example/hero.png"><img src="https://cdn.example/two.png">)
    )

    result = lead_image_for(html).remainder

    expect(result).to include("two.png")
  end

  # The feed reads #url at ingest and never renders a caption, so none of this
  # can change which image a row shows.
  it "reads the same lead image whether or not a figure wraps it" do
    html = figure_holding(%(<img src="https://cdn.example/hero.png">))

    result = lead_image_for(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end
end
