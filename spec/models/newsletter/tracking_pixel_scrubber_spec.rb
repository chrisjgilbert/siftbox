require "rails_helper"

# Read through Newsletter::Body#document, which is the only thing that runs
# this scrubber. Asserting on the surviving markup is the behaviour; the
# scrubber's own return values are not.
RSpec.describe Newsletter::TrackingPixelScrubber do
  def scrubbed_markup(html)
    Newsletter::Body.new(html).document.to_html
  end

  it "removes an image sized in pixels down to a beacon" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" width="1" height="1">))

    expect(result).not_to include("track.example")
  end

  it "removes an image sized to nothing at all" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" width="0" height="0">))

    expect(result).not_to include("track.example")
  end

  # A size is a count of pixels whether or not the sender spells the unit, and
  # plenty of them spell it in the attribute as well as in the CSS.
  it "removes an image whose attribute size carries a pixel unit" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" width="1px" height="1px">))

    expect(result).not_to include("track.example")
  end

  it "removes an image whose size is padded with whitespace" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" width=" 1 ">))

    expect(result).not_to include("track.example")
  end

  it "removes an image the sender sized in CSS down to a beacon" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" style="width:1px">))

    expect(result).not_to include("track.example")
  end

  it "removes an image the sender hid outright" do
    result = scrubbed_markup(%(<img src="https://track.example/o.gif" style="display:none">))

    expect(result).not_to include("track.example")
  end

  # Senders park beacons inside a hidden container rather than hiding the
  # image itself, which reads as an ordinary image one node down.
  it "removes an image its container hides" do
    result = scrubbed_markup(%(<div style="display:none"><img src="https://track.example/o.gif"></div>))

    expect(result).not_to include("track.example")
  end

  it "keeps an image that declares a real size" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" width="600" height="300">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image whose attribute size carries a pixel unit at a real size" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" width="600px">))

    expect(result).to include("cdn.example/hero.png")
  end

  # Most real images carry no dimensions at all, which is also why this
  # narrows the gap rather than closing it.
  it "keeps an image that declares no size at all" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png">))

    expect(result).to include("cdn.example/hero.png")
  end

  # line-height:0 is the standard fix for the gap Outlook leaves under an
  # image, so it rides on a large share of real newsletter artwork. Matching
  # it as a height deleted the picture.
  it "keeps an image whose only tiny value is its line height" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" style="display:block;line-height:0">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image whose only tiny value is its border width" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" style="border-width:0;width:600px">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image whose real height follows a tiny minimum height" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" style="min-height:1px;height:400px">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image sized in a percentage rather than pixels" do
    result = scrubbed_markup(%(<img src="https://cdn.example/hero.png" width="100%">))

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps the images beside one it removed" do
    html = %(<img src="https://track.example/o.gif" width="1"><img src="https://cdn.example/hero.png">)

    expect(scrubbed_markup(html)).to include("cdn.example/hero.png")
  end

  it "keeps the markup beside an image it removed" do
    html = %(<p>Morning</p><img src="https://track.example/o.gif" width="1">)

    expect(scrubbed_markup(html)).to include("<p>Morning</p>")
  end
end
