require "rails_helper"

# Read through Newsletter::Body, which is the only thing that runs this
# scrubber. Asserting on the surviving markup is the behaviour; the scrubber's
# own return values are not.
RSpec.describe Newsletter::TrackingPixelScrubber do
  def scrubbed(html)
    Newsletter::Body.new(html).scrubbed
  end

  it "removes an image sized in pixels down to a beacon" do
    result = scrubbed(%(<img src="https://track.example/o.gif" width="1" height="1">))

    expect(result).not_to include("track.example")
  end

  it "removes an image the sender sized in CSS down to a beacon" do
    result = scrubbed(%(<img src="https://track.example/o.gif" style="width:1px">))

    expect(result).not_to include("track.example")
  end

  it "removes an image the sender hid outright" do
    result = scrubbed(%(<img src="https://track.example/o.gif" style="display:none">))

    expect(result).not_to include("track.example")
  end

  # line-height:0 is the standard fix for the gap Outlook leaves under an
  # image, so it rides on a large share of real newsletter artwork. Matching
  # it as a height deleted the picture.
  it "keeps an image whose only tiny value is its line height" do
    result = scrubbed(%(<img src="https://cdn.example/hero.png" style="display:block;line-height:0">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image whose only tiny value is its border width" do
    result = scrubbed(%(<img src="https://cdn.example/hero.png" style="border-width:0;width:600px">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image whose real height follows a tiny minimum height" do
    result = scrubbed(%(<img src="https://cdn.example/hero.png" style="min-height:1px;height:400px">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image sized in a percentage rather than pixels" do
    result = scrubbed(%(<img src="https://cdn.example/hero.png" width="100%">))

    expect(result).to include("cdn.example/hero.png")
  end

  # Senders park beacons inside a hidden container rather than hiding the
  # image itself, which reads as an ordinary image one node down.
  it "removes an image its container hides" do
    result = scrubbed(%(<div style="display:none"><img src="https://track.example/o.gif"></div>))

    expect(result).not_to include("track.example")
  end

  it "keeps the images beside one it removed" do
    html = %(<img src="https://track.example/o.gif" width="1"><img src="https://cdn.example/hero.png">)

    expect(scrubbed(html)).to include("cdn.example/hero.png")
  end
end
