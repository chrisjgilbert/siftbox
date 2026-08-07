require "rails_helper"

RSpec.describe NewslettersHelper do
  # The reader view is handed a presenter, not a record, so the helper is
  # exercised through one here too.
  def body_for(newsletter)
    helper.newsletter_body(Newsletter::Presenter.new(newsletter))
  end

  it "keeps the tags the reader needs" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hello <em>there</em></p>")

    expect(body_for(newsletter)).to eq("<p>Hello <em>there</em></p>")
  end

  it "drops the sender's inline styling" do
    newsletter = build_stubbed(:newsletter, body_html: %(<p style="color:red">Hi</p>))

    expect(body_for(newsletter)).to eq("<p>Hi</p>")
  end

  it "drops the sender's classes" do
    newsletter = build_stubbed(:newsletter, body_html: %(<p class="mso">Hi</p>))

    expect(body_for(newsletter)).to eq("<p>Hi</p>")
  end

  it "drops table layout attributes but keeps the cell content" do
    body = %(<table bgcolor="#fff"><tr><td width="600">Hi</td></tr></table>)
    newsletter = build_stubbed(:newsletter, body_html: body)

    expect(body_for(newsletter)).to include("<td>Hi</td>")
  end

  # The size has to survive the allowlist as well as be set, and those are two
  # different files — ATTRIBUTES here, Newsletter::Body#apply_stored_sizes
  # there.
  it "keeps the stored size on an image this app hosts" do
    newsletter = create(:newsletter)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(Rails.root.join("spec/fixtures/files/logo.png").binread),
      filename: "logo.png",
      content_type: "image/png"
    )
    newsletter.inline_images.attach(blob)
    blob.analyze
    newsletter.update!(body_html: %(<img src="#{newsletter.inline_image_path(blob)}">))

    expect(body_for(newsletter)).to include(%(width="8"), %(height="4"))
  end

  it "removes script tags entirely" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hi</p><script>alert(1)</script>")

    expect(body_for(newsletter)).not_to include("alert")
  end

  it "removes a javascript href" do
    newsletter = build_stubbed(:newsletter, body_html: %(<a href="javascript:alert(1)">x</a>))

    expect(body_for(newsletter)).not_to include("javascript")
  end

  it "keeps a real link" do
    newsletter = build_stubbed(:newsletter, body_html: %(<a href="https://example.com">x</a>))

    expect(body_for(newsletter)).to include(%(href="https://example.com"))
  end

  it "strips tracking pixels before sanitizing" do
    body = %(<p>Hi</p><img src="https://track.example/o.gif" width="1" height="1">)
    newsletter = build_stubbed(:newsletter, body_html: body)

    expect(body_for(newsletter)).not_to include("track.example")
  end

  it "returns output marked safe so the view needs no html_safe call" do
    newsletter = build_stubbed(:newsletter, body_html: "<p>Hi</p>")

    expect(body_for(newsletter)).to be_html_safe
  end
end
