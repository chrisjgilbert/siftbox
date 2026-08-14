require "rails_helper"

RSpec.describe Newsletter::Prose do
  # The shape a Substack issue actually arrives in: the app bar above the
  # masthead, the forwarding prompt, the reaction row under the post, and the
  # footer the platform appends to every issue of every publication.
  def substack_issue
    <<~HTML
      <table><tr><td>
        <a href="https://open.substack.com/pub/moneystuff/p/figma?utm_source=email">READ IN APP</a>
      </td></tr></table>
      <p>Forwarded this email? <a href="https://moneystuff.substack.com/subscribe">Subscribe here</a> for more</p>
      <h1>The Figma S-1</h1>
      <p>Figma filed its S-1 on Tuesday, and the numbers are rather better
      than anyone outside the company seems to have expected.</p>
      <table><tr>
        <td><a href="https://substack.com/like">Like</a></td>
        <td><a href="https://substack.com/comment">Comment</a></td>
        <td><a href="https://substack.com/restack">Restack</a></td>
      </tr></table>
      <div>
        <p>You're receiving this because you subscribed to Money Stuff.</p>
        <p><a href="https://substack.com/away">Unsubscribe</a> | <a href="https://substack.com/prefs">Update your preferences</a></p>
        <p>228 Park Ave S, PMB 71196, New York, NY 10003</p>
        <p>&copy; 2026 Matt Levine</p>
      </div>
    HTML
  end

  # A link roundup, the other common shape: a view-in-browser bar, items that
  # are almost entirely link text, a share row and a plainer footer.
  def link_roundup_issue
    <<~HTML
      <div><a href="https://mail.example.com/web/1">View this email in your browser</a></div>
      <h2>Today's links</h2>
      <ul>
        <li><a href="https://example.com/sleep">The case against sleep</a> — a long argument, well made.</li>
        <li><a href="https://example.com/figma">Figma's S-1, annotated</a></li>
      </ul>
      <p>Share: <a href="#">Twitter</a> &middot; <a href="#">Facebook</a> &middot; <a href="#">LinkedIn</a></p>
      <p>No longer want these emails? <a href="https://mail.example.com/u/1">Unsubscribe</a>.</p>
      <p>AI News, 2261 Market Street #4818, San Francisco, CA 94114</p>
    HTML
  end

  # One sentence repeated is enough: the cap is about length, and a body that
  # reaches it is several hundred paragraphs of something.
  def sentence
    "Figma filed its S-1 on Tuesday and the numbers surprised everyone. "
  end

  def issue_longer_than(characters)
    "<p>#{sentence * ((characters / sentence.length) + 1)}</p>"
  end

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

  it "keeps the issue's own prose" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).to include("The Figma S-1", "Figma filed its S-1 on Tuesday")
  end

  it "removes the app bar above the masthead" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("READ IN APP")
  end

  it "removes the forwarding prompt" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("Forwarded this email")
  end

  it "removes the reaction row under the post" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("Restack")
  end

  it "removes the line saying why the email arrived" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("You're receiving this")
  end

  it "removes the unsubscribe and preferences footer" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("Unsubscribe", "Update your preferences")
  end

  it "removes the address block" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("228 Park Ave S")
  end

  it "removes the copyright line" do
    result = Newsletter::Prose.new(Newsletter::Body.new(substack_issue)).text

    expect(result).not_to include("2026 Matt Levine")
  end

  it "removes the view-in-browser bar" do
    result = Newsletter::Prose.new(Newsletter::Body.new(link_roundup_issue)).text

    expect(result).not_to include("View this email in your browser")
  end

  it "removes a row of share links" do
    result = Newsletter::Prose.new(Newsletter::Body.new(link_roundup_issue)).text

    expect(result).not_to include("LinkedIn")
  end

  it "removes the opt-out line at the foot of a roundup" do
    result = Newsletter::Prose.new(Newsletter::Body.new(link_roundup_issue)).text

    expect(result).not_to include("No longer want these emails")
  end

  it "keeps every item of a link roundup" do
    result = Newsletter::Prose.new(Newsletter::Body.new(link_roundup_issue)).text

    expect(result).to include("The case against sleep", "Figma's S-1, annotated")
  end

  # The chrome rules strip boilerplate every issue carries, not anything that
  # looks promotional. Anything dropped here is something the editor cannot
  # cite, and the completeness guarantee says every newsletter gets cited.
  it "keeps prose that happens to mention unsubscribing" do
    html = "<p>The complaint is that the unsubscribe link is buried three " \
           "scrolls down, which is now a fineable offence in Germany.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to include("unsubscribe link is buried")
  end

  it "keeps a sentence that opens by asking to be shared" do
    html = "<p>Share this with the one person you know who still reads S-1s.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to include("Share this with the one person")
  end

  it "keeps an address that is part of the story" do
    html = "<p>The hearing is at 500 Pearl Street, New York, NY 10007, on Thursday.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to include("500 Pearl Street")
  end

  # The truncation point and the upgrade prompt are how the editor tells a
  # paywalled stub from a full piece, and the PRD has it report a teaser
  # honestly rather than write it up. Strip the prompt as a subscribe CTA and
  # the stub reads as a complete but strangely thin article.
  it "keeps the upgrade prompt that marks a paywalled stub" do
    html = "<p>Keep reading with a 7-day free trial.</p>" \
           "<p>Subscribe to The Diff to keep reading this post.</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to include("Subscribe to The Diff to keep reading")
  end

  # Bodies run to hundreds of kilobytes and the window holds ten to twenty of
  # them at once.
  it "caps a body that runs past the limit" do
    html = issue_longer_than(Newsletter::Prose::MAXIMUM_CHARACTERS)

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result.length).to be <= Newsletter::Prose::MAXIMUM_CHARACTERS
  end

  # A half word is a token the editor could quote as though the sender wrote
  # it, and the last one before the cap is the one it is likeliest to reach
  # for.
  it "cuts the text on a word boundary" do
    html = issue_longer_than(Newsletter::Prose::MAXIMUM_CHARACTERS)

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(sentence.split).to include(result.lines.first.split.last)
  end

  # Truncation is one of the things the editor reads a paywalled stub by, so
  # a cap that cut silently would have it report our own limit as the
  # sender's paywall.
  it "says where it cut" do
    html = issue_longer_than(Newsletter::Prose::MAXIMUM_CHARACTERS)

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to end_with(Newsletter::Prose::OMISSION)
  end

  it "leaves a newsletter that fits alone" do
    html = "<p>#{sentence}</p>"

    result = Newsletter::Prose.new(Newsletter::Body.new(html)).text

    expect(result).to eq(sentence.strip)
  end
end
