require "rails_helper"

RSpec.describe Newsletter::Body do
  # Pruning is what makes #text safe to read, so it is asserted through the
  # text rather than through the markup: left alone, the code inside a
  # <script> and the rules inside a <style> read back as prose into the
  # snippet and into what the editor is shown.
  it "reads no text out of a script tag" do
    result = Newsletter::Body.new(%(<p>Hi</p><script>alert(1)</script>)).text

    expect(result).not_to include("alert")
  end

  it "reads no text out of a style block" do
    result = Newsletter::Body.new(%(<style>p { color: red }</style><p>Hi</p>)).text

    expect(result).not_to include("color: red")
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
