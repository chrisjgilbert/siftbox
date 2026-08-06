require "rails_helper"

RSpec.describe NewslettersMailbox, type: :mailbox do
  def newsletter_mail(**headers)
    Mail.new({
      to: "newsletters@example.com",
      from: "Ruby Weekly <peter@rubyweekly.com>",
      subject: "Issue 742"
    }.merge(headers)) do
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>Morning</p>"
      end
    end
  end

  it "stores any inbound mail as a newsletter" do
    receive_inbound_email_from_source(newsletter_mail.to_s)

    expect(Newsletter.count).to eq(1)
  end

  it "routes mail to any recipient, since one address takes every subscription" do
    receive_inbound_email_from_source(newsletter_mail(to: "anything@example.com").to_s)

    expect(Newsletter.count).to eq(1)
  end

  it "discards mail Postmark scored as spam" do
    mail = newsletter_mail
    mail["X-Spam-Score"] = "9.4"

    receive_inbound_email_from_source(mail.to_s)

    expect(Newsletter.count).to eq(0)
  end

  it "keeps mail scoring below the spam threshold" do
    mail = newsletter_mail
    mail["X-Spam-Score"] = "0.4"

    receive_inbound_email_from_source(mail.to_s)

    expect(Newsletter.count).to eq(1)
  end

  it "marks discarded spam as delivered rather than failed" do
    mail = newsletter_mail
    mail["X-Spam-Score"] = "9.4"

    inbound_email = receive_inbound_email_from_source(mail.to_s)

    expect(inbound_email).to be_delivered
  end
end
