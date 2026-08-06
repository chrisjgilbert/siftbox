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

    expect(newsletter.reload.body_html).to include("/rails/active_storage/")
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

  it "does nothing when the mail carries no inline parts" do
    newsletter = create(:newsletter, body_html: "<p>Morning</p>")

    Newsletter::InlineImages.new(newsletter, []).attach

    expect(newsletter.reload.body_html).to eq("<p>Morning</p>")
  end
end
