require "rails_helper"

RSpec.describe NewslettersHelper do
  it "keeps the tags the reader needs" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hello <em>there</em></p>")

    expect(helper.newsletter_body(newsletter)).to eq("<p>Hello <em>there</em></p>")
  end

  it "drops the sender's inline styling" do
    newsletter = build_stubbed(:newsletter, body_html: %(<p style="color:red">Hi</p>))

    expect(helper.newsletter_body(newsletter)).to eq("<p>Hi</p>")
  end

  it "drops the sender's classes" do
    newsletter = build_stubbed(:newsletter, body_html: %(<p class="mso">Hi</p>))

    expect(helper.newsletter_body(newsletter)).to eq("<p>Hi</p>")
  end

  it "drops table layout attributes but keeps the cell content" do
    body = %(<table bgcolor="#fff"><tr><td width="600">Hi</td></tr></table>)
    newsletter = build_stubbed(:newsletter, body_html: body)

    expect(helper.newsletter_body(newsletter)).to include("<td>Hi</td>")
  end

  it "removes script tags entirely" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hi</p><script>alert(1)</script>")

    expect(helper.newsletter_body(newsletter)).not_to include("alert")
  end

  it "removes a javascript href" do
    newsletter = build_stubbed(:newsletter, body_html: %(<a href="javascript:alert(1)">x</a>))

    expect(helper.newsletter_body(newsletter)).not_to include("javascript")
  end

  it "keeps a real link" do
    newsletter = build_stubbed(:newsletter, body_html: %(<a href="https://example.com">x</a>))

    expect(helper.newsletter_body(newsletter)).to include(%(href="https://example.com"))
  end

  it "strips tracking pixels before sanitizing" do
    body = %(<p>Hi</p><img src="https://track.example/o.gif" width="1" height="1">)
    newsletter = build_stubbed(:newsletter, body_html: body)

    expect(helper.newsletter_body(newsletter)).not_to include("track.example")
  end

  it "returns output marked safe so the view needs no html_safe call" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hi</p>")

    expect(helper.newsletter_body(newsletter)).to be_html_safe
  end
end
