require "rails_helper"

RSpec.describe Newsletter::Prose do
  it "reads the prose out of the markup" do
    html = "<h1>The Figma S-1</h1><p>Figma filed on Tuesday.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("The Figma S-1\nFigma filed on Tuesday.")
  end

  it "puts each block of prose on its own line" do
    html = "<p>Hello there</p><p>Goodbye now</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Hello there\nGoodbye now")
  end

  it "puts each cell of a layout table on its own line" do
    html = "<table><tr><td>Read more</td><td>Issue 42</td></tr></table>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Read more\nIssue 42")
  end

  # Newsletter::Body's own #text answers "sub scribe" here, because it joins
  # every text node with a space. It can afford to: it feeds a word count and
  # a snippet. The editor is asked to quote what it reads.
  it "keeps a word broken up by inline markup whole" do
    html = "<p>Nobody wants to <em>un</em>subscribe from this one.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Nobody wants to unsubscribe from this one.")
  end

  it "keeps a line break inside a block as a space" do
    html = "<p>Line one<br>Line two</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Line one Line two")
  end

  it "collapses the whitespace a sender's indentation leaves behind" do
    html = "<p>\n      Figma\n      filed\n    </p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Figma filed")
  end

  # Substack pads a preheader out to the width of an inbox preview with
  # hundreds of these. They are invisible, they are not whitespace, and
  # squish leaves every one of them in place.
  it "drops the zero-width padding a preheader is spaced with" do
    html = "<div>Figma filed\u200C\u200B\u200C\u200B\uFEFF</div>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Figma filed")
  end

  # A link roundup is mostly link text, and the PRD wants each of its items
  # to reach the editor as a story candidate.
  it "keeps the text of a link" do
    html = %(<li><a href="https://example.com/sleep">The case against sleep</a></li>)

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("The case against sleep")
  end

  # A URL is a token the editor cannot follow and must not invent from. The
  # sentence around it is still worth reading.
  it "drops a URL the sender printed as text" do
    html = "<p>The filing is at https://sec.gov/figma-s1?utm_source=email if you want it.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("The filing is at if you want it.")
  end

  it "drops a bare domain the sender printed as text" do
    html = "<p>Mirrored at www.example.com overnight.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Mirrored at overnight.")
  end

  it "drops a line that is nothing but a URL" do
    html = "<p>Figma filed.</p><p>https://sec.gov/figma-s1</p><p>Nobody expected it.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq("Figma filed.\nNobody expected it.")
  end
end
