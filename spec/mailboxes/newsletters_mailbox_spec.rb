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

  def scored_mail(score)
    newsletter_mail.tap { |mail| mail["X-Spam-Score"] = score }
  end

  it "discards mail Postmark scored as spam" do
    receive_inbound_email_from_source(scored_mail("9.4").to_s)

    expect(Newsletter.count).to eq(0)
  end

  it "keeps mail scoring below the spam threshold" do
    receive_inbound_email_from_source(scored_mail("0.4").to_s)

    expect(Newsletter.count).to eq(1)
  end

  it "records discarded spam as bounced rather than delivered" do
    inbound_email = receive_inbound_email_from_source(scored_mail("9.4").to_s)

    expect(inbound_email).to be_bounced
  end

  # `bounced!` only sets the status. Sending anything back would deliver it to
  # the forged sender address on the spam.
  #
  # Asserts on the enqueued job, not on ActionMailer::Base.deliveries:
  # `bounce_with` sends through `deliver_later`, which the test queue adapter
  # enqueues and never performs, so deliveries would stay empty either way.
  it "sends nothing back to the forged sender of discarded spam" do
    expect {
      receive_inbound_email_from_source(scored_mail("9.4").to_s)
    }.not_to have_enqueued_mail
  end

  it "records mail it accepted as delivered" do
    inbound_email = receive_inbound_email_from_source(newsletter_mail.to_s)

    expect(inbound_email).to be_delivered
  end

  # Anything raised in processing loses the newsletter, and a header that
  # repeats is ordinary in mail forwarded through another spam filter.
  it "stores mail carrying the spam score header twice" do
    mail = newsletter_mail
    mail.header["X-Spam-Score"] = "0.1"
    mail.header["X-Spam-Score"] = "0.2"

    receive_inbound_email_from_source(mail.to_s)

    expect(Newsletter.count).to eq(1)
  end

  it "stores mail whose From header is not a parseable address" do
    receive_inbound_email_from_source(
      "From: Ruby Weekly\nTo: news@example.com\nSubject: Issue 742\n\nMorning"
    )

    expect(Newsletter.count).to eq(1)
  end

  it "stores a redelivery once rather than failing on it" do
    source = newsletter_mail(message_id: "<issue-742@rubyweekly.com>").to_s
    receive_inbound_email_from_source(source)

    inbound_email = receive_inbound_email_from_source("#{source}\n")

    expect(inbound_email).to be_delivered
  end
end
