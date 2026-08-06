require "rails_helper"

RSpec.describe Newsletter::Body do
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
end
