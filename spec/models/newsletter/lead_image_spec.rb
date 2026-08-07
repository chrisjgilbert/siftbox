require "rails_helper"

RSpec.describe Newsletter::LeadImage do
  it "takes the first image in the body" do
    html = %(<img src="https://cdn.example/hero.png"><img src="https://cdn.example/two.png">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the body carries no images" do
    result = Newsletter::LeadImage.new("<p>Morning</p>").url

    expect(result).to eq("")
  end

  it "has no url when the body is empty" do
    result = Newsletter::LeadImage.new("").url

    expect(result).to eq("")
  end

  # The scrubber runs first, so a beacon is gone before the first image is
  # picked. Without that order every newsletter leads with a 1x1 gif.
  it "passes over a tracking pixel to reach the real image" do
    html = %(<img src="https://track.example/o.gif" width="1"><img src="https://cdn.example/hero.png">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the only image is a tracking pixel" do
    html = %(<img src="https://track.example/o.gif" width="1" height="1">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("")
  end

  # A data: URI is usually a spacer or a bullet, and storing one puts
  # kilobytes of base64 into a column the feed reads on every row.
  it "passes over a data uri to reach a hosted image" do
    html = %(<img src="data:image/gif;base64,R0lGOD"><img src="https://cdn.example/hero.png">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  it "has no url when the only image is a data uri" do
    result = Newsletter::LeadImage.new(%(<img src="data:image/gif;base64,R0lGOD">)).url

    expect(result).to eq("")
  end

  it "has no url for an image with no source at all" do
    result = Newsletter::LeadImage.new("<img>").url

    expect(result).to eq("")
  end

  # A cid: reference means nothing to a browser. One surviving here is an
  # inline image that failed to attach, not a lead.
  it "passes over an unrewritten cid reference" do
    html = %(<img src="cid:logo@sender"><img src="https://cdn.example/hero.png">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("https://cdn.example/hero.png")
  end

  # Newsletter::InlineImages rewrites cid: references to app paths before
  # this runs, so an image carried inside the message is a legitimate lead.
  it "takes an inline image rewritten to an app path" do
    html = %(<img src="/newsletters/1/images/abc">)

    result = Newsletter::LeadImage.new(html).url

    expect(result).to eq("/newsletters/1/images/abc")
  end

  it "drops the lead image from the remainder" do
    html = %(<p>Morning</p><img src="https://cdn.example/hero.png">)

    result = Newsletter::LeadImage.new(html).remainder

    expect(result).not_to include("hero.png")
  end

  it "keeps the rest of the body in the remainder" do
    html = %(<p>Morning</p><img src="https://cdn.example/hero.png">)

    result = Newsletter::LeadImage.new(html).remainder

    expect(result).to include("<p>Morning</p>")
  end

  it "keeps later images in the remainder" do
    html = %(<img src="https://cdn.example/hero.png"><img src="https://cdn.example/two.png">)

    result = Newsletter::LeadImage.new(html).remainder

    expect(result).to include("two.png")
  end

  it "leaves the body alone when there is no lead image to drop" do
    result = Newsletter::LeadImage.new("<p>Morning</p>").remainder

    expect(result).to include("<p>Morning</p>")
  end

  # The two readers run in different places — extraction at ingest, the
  # remainder at render — but nothing stops one instance answering both, and
  # a caller should not have to know that #remainder mutates the document.
  it "still knows the url after the remainder has been taken" do
    lead = Newsletter::LeadImage.new(%(<img src="https://cdn.example/hero.png">))

    lead.remainder

    expect(lead.url).to eq("https://cdn.example/hero.png")
  end
end
