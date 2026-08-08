require "rails_helper"

RSpec.describe Newsletter::Body do
  # Also pins the order of the passes: #strip_sender_sizes takes every
  # sender-written width and height, and the scrubber reads exactly those to
  # recognise a tracker. Strip them first and this goes green while the
  # tracker survives.
  it "removes a one-pixel tracking image" do
    html = %(<p>Hi</p><img src="https://track.example/o.gif" width="1" height="1">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "removes a zero-width tracking image" do
    html = %(<img src="https://track.example/o.gif" width="0" height="0">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "removes a tracking image sized in pixel units" do
    html = %(<img src="https://track.example/o.gif" width="1px" height="1px">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "removes a tracking image whose size is padded with whitespace" do
    html = %(<img src="https://track.example/o.gif" width=" 1 ">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "removes a tracking image sized in a style attribute" do
    html = %(<img src="https://track.example/o.gif" style="width:1px;height:1px">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "removes an image the sender hid with display none" do
    html = %(<img src="https://track.example/o.gif" style="display:none">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("track.example")
  end

  it "keeps an image sized in pixel units at a real size" do
    html = %(<img src="https://cdn.example/hero.png" width="600px">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image that declares a real size" do
    html = %(<img src="https://cdn.example/hero.png" width="600" height="300">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image that declares no size at all" do
    html = %(<img src="https://cdn.example/hero.png">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).to include("cdn.example/hero.png")
  end

  it "keeps an image sized in percentages" do
    html = %(<img src="https://cdn.example/hero.png" width="100%">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).to include("cdn.example/hero.png")
  end

  it "removes a script tag along with the code inside it" do
    html = %(<p>Hi</p><script>alert(1)</script>)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("alert")
  end

  it "removes a style block along with the rules inside it" do
    html = %(<style>p { color: red }</style><p>Hi</p>)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("color: red")
  end

  it "leaves surrounding markup alone" do
    html = %(<p>Morning</p><img src="https://track.example/o.gif" width="1">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).to include("<p>Morning</p>")
  end

  it "sets the stored size on an image this app hosts" do
    html = %(<img src="/newsletters/1/images/9">)

    result = Newsletter::Body.new(html, dimensions: { "/newsletters/1/images/9" => [ 69, 69 ] }).scrubbed

    expect(result).to include(%(width="69"), %(height="69"))
  end

  # The sender's own numbers are a claim about an image this app now stores
  # and has measured, and they are routinely wrong — a 600px banner declared
  # at 100% or at the width of some other client's column.
  it "replaces the sender's size with the stored one" do
    html = %(<img src="/newsletters/1/images/9" width="600" height="80">)

    result = Newsletter::Body.new(html, dimensions: { "/newsletters/1/images/9" => [ 69, 69 ] }).scrubbed

    expect(result).to include(%(width="69"), %(height="69"))
  end

  # A download that failed leaves the sender's URL in place, so there is no
  # stored blob to measure and nothing trustworthy to put here.
  it "drops the size from an image this app does not host" do
    html = %(<img src="https://cdn.example/banner.png" width="600" height="80">)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("width=", "height=")
  end

  # Tables are unwrapped to block in CSS, so a sender's column width would
  # fight the reading column rather than describe anything.
  it "drops the size from everything that is not an image" do
    html = %(<table><tr><td width="600" height="40">Hi</td></tr></table>)

    result = Newsletter::Body.new(html).scrubbed

    expect(result).not_to include("width=", "height=")
  end

  # The browser reserves space from the ratio of the two, so half a pair
  # reserves nothing and an empty height is markup nothing reads.
  it "sets neither size when only one of the pair is known" do
    html = %(<img src="/newsletters/1/images/9">)

    result = Newsletter::Body.new(html, dimensions: { "/newsletters/1/images/9" => [ 69, nil ] }).scrubbed

    expect(result).not_to include("width=", "height=")
  end

  # Nokogiri runs the text nodes together, so the last word of one block and
  # the first of the next arrive as one. The snippet reads as a typo and the
  # reading time loses a word per block.
  it "separates the text of one block from the next" do
    result = Newsletter::Body.new("<p>Hello there</p><p>Goodbye now</p>").text

    expect(result).to eq("Hello there Goodbye now")
  end

  it "separates the text of one table cell from the next" do
    html = %(<table><tr><td>Read more</td><td>Issue 42</td></tr></table>)

    result = Newsletter::Body.new(html).text

    expect(result).to eq("Read more Issue 42")
  end

  it "separates the text either side of a line break" do
    result = Newsletter::Body.new("<p>Line one<br>Line two</p>").text

    expect(result).to eq("Line one Line two")
  end

  it "keeps a sentence broken up by inline markup as one run of words" do
    result = Newsletter::Body.new("<p>Rails <em>8</em> shipped today</p>").text

    expect(result).to eq("Rails 8 shipped today")
  end
end
