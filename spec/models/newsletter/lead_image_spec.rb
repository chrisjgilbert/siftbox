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
end
