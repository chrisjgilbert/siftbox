require "rails_helper"

RSpec.describe Newsletter::InlineImages do
  def mail_with_inline_image(html:)
    mail = Mail.new(from: "peter@rubyweekly.com", subject: "Issue 742") do
      html_part do
        content_type "text/html; charset=UTF-8"
        body html
      end
    end

    mail.attachments["logo.png"] = {
      mime_type: "image/png",
      content: "not-really-a-png"
    }
    mail.attachments["logo.png"].content_id = "<logo@rubyweekly.com>"
    mail
  end

  it "attaches the inline part to the newsletter" do
    mail = mail_with_inline_image(html: %(<img src="cid:logo@rubyweekly.com">))
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.inline_images).to be_attached
  end

  it "rewrites the cid reference to a path the browser can fetch" do
    mail = mail_with_inline_image(html: %(<img src="cid:logo@rubyweekly.com">))
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.reload.body_html).to include("/newsletters/#{newsletter.id}/images/")
  end

  it "leaves no cid reference behind" do
    mail = mail_with_inline_image(html: %(<img src="cid:logo@rubyweekly.com">))
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.reload.body_html).not_to include("cid:")
  end

  it "leaves a hotlinked image alone" do
    mail = mail_with_inline_image(html: %(<img src="https://cdn.example/hero.png">))
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.reload.body_html).to include("https://cdn.example/hero.png")
  end

  def mail_with_unnamed_inline_image
    Mail.read_from_string(
      "From: a@b.com\nSubject: s\n" \
      "Content-Type: multipart/related; boundary=X\n\n--X\n" \
      "Content-Type: text/html\n\n<img src=\"cid:logo@b.com\">\n--X\n" \
      "Content-Type: image/png\nContent-ID: <logo@b.com>\n" \
      "Content-Disposition: inline\nContent-Transfer-Encoding: base64\n\naGk=\n--X--\n"
    )
  end

  it "stores an inline part that declares a Content-ID but no filename" do
    mail = mail_with_unnamed_inline_image
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.all_parts).attach

    expect(newsletter.inline_images).to be_attached
  end

  it "rewrites a cid reference whose part had no filename" do
    mail = mail_with_unnamed_inline_image
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.all_parts).attach

    expect(newsletter.reload.body_html).not_to include("cid:")
  end

  it "does nothing when the mail carries no inline parts" do
    newsletter = create(:newsletter, body_html: "<p>Morning</p>")

    Newsletter::InlineImages.new(newsletter, []).attach

    expect(newsletter.reload.body_html).to eq("<p>Morning</p>")
  end

  def mail_with_two_inline_images(html:, first:, second:)
    mail = Mail.new(from: "peter@rubyweekly.com", subject: "Issue 742") do
      html_part do
        content_type "text/html; charset=UTF-8"
        body html
      end
    end

    { "one.png" => first, "two.png" => second }.each do |name, identifier|
      mail.attachments[name] = { mime_type: "image/png", content: name }
      mail.attachments[name].content_id = "<#{identifier}>"
    end
    mail
  end

  # Regexp.union alternates in the order it is given and Ruby matches
  # leftmost-first, not longest. With the shorter reference listed first it
  # matched inside the longer one and left the tail behind.
  it "rewrites a reference that another reference is a prefix of" do
    mail = mail_with_two_inline_images(
      html: %(<img src="cid:img1"><img src="cid:img12">),
      first: "img1", second: "img12"
    )
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    sources = newsletter.reload.body_html.scan(/src="([^"]*)"/).flatten

    expect(sources).to all(match(%r{\A/newsletters/\d+/images/\d+\z}))
  end

  it "points each reference at its own blob" do
    mail = mail_with_two_inline_images(
      html: %(<img src="cid:img1"><img src="cid:img12">),
      first: "img1", second: "img12"
    )
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    paths = newsletter.reload.body_html.scan(%r{/newsletters/\d+/images/\d+})

    expect(paths.uniq.length).to eq(2)
  end

  # Mail::Message#cid URI-escapes the Content-ID, but the sender's src carries
  # what they wrote. Keying on cid alone left the reference unrewritten.
  it "rewrites a reference whose content id needs escaping" do
    mail = mail_with_inline_image(html: %(<img src="cid:a b@rubyweekly.com">))
    mail.attachments["logo.png"].content_id = "<a b@rubyweekly.com>"
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.reload.body_html).not_to include("cid:")
  end

  # The serving controller answers 404 for anything outside its allowlist, so
  # rewriting the reference would turn a missing image into a broken one and
  # let it win the lead.
  it "leaves a part this app will not serve as a cid reference" do
    mail = mail_with_inline_image(html: %(<img src="cid:logo@rubyweekly.com">))
    mail.attachments["logo.png"].content_type = "image/svg+xml"
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach

    expect(newsletter.reload.body_html).to include("cid:logo@rubyweekly.com")
  end

  # Built by parsing rather than with Mail.new: assigning an attachment
  # encodes it there and then, so a Content-Transfer-Encoding set afterwards
  # never reaches the body and the header is a lie the object never tells.
  # Action Mailbox parses, so only this shape is the one that arrives.
  def mail_with_inline_image_encoded(encoding)
    Mail.read_from_string(
      "From: a@b.com\r\nSubject: s\r\n" \
      "Content-Type: multipart/related; boundary=X\r\n\r\n--X\r\n" \
      "Content-Type: text/html\r\n\r\n<img src=\"cid:logo@b.com\">\r\n--X\r\n" \
      "Content-Type: image/png\r\nContent-ID: <logo@b.com>\r\n" \
      "Content-Disposition: inline\r\n" \
      "Content-Transfer-Encoding: #{encoding}\r\n\r\naGk=\r\n--X--\r\n"
    )
  end

  # Newsletter::InboundMessage already survives an unrecognised
  # Content-Transfer-Encoding on the body. The same header on an image part
  # reached here instead, where anything raised loses the whole newsletter.
  it "keeps the newsletter when a part declares an unknown transfer encoding" do
    mail = mail_with_inline_image_encoded("bogus-encoding")
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.all_parts).attach

    expect(newsletter.reload.body_html).to eq(%(<img src="cid:logo@b.com">))
  end

  # Storing the raw source the way the body reader does would mean serving
  # undecoded base64 as an image: broken in the reader, and able to win
  # lead_image_url and break the feed row too.
  it "stores no blob for a part that declares an unknown transfer encoding" do
    mail = mail_with_inline_image_encoded("bogus-encoding")
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.all_parts).attach

    expect(newsletter.inline_images).not_to be_attached
  end

  it "stores a part whose transfer encoding it recognises" do
    mail = mail_with_inline_image_encoded("base64")
    newsletter = create(:newsletter, body_html: mail.html_part.decoded)

    Newsletter::InlineImages.new(newsletter, mail.all_parts).attach

    expect(newsletter.inline_images).to be_attached
  end
end
