require "rails_helper"

RSpec.describe Newsletter::InboundMessage do
  def inbound_mail(html: "<p>Morning</p>", text: nil, **headers)
    attributes = {
      from: "Ruby Weekly <peter@rubyweekly.com>",
      subject: "Issue 742"
    }.merge(headers)

    Mail.new(attributes) do
      html_part do
        content_type "text/html; charset=UTF-8"
        body html
      end

      if text
        text_part { body text }
      end
    end
  end

  it "stores the sender name and address separately" do
    message = Newsletter::InboundMessage.new(mail: inbound_mail)

    newsletter = message.save

    expect(newsletter).to have_attributes(
      sender_name: "Ruby Weekly",
      sender_email: "peter@rubyweekly.com"
    )
  end

  it "stores the sender address when the sender has no display name" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(from: "peter@rubyweekly.com")
    )

    newsletter = message.save

    expect(newsletter.sender_email).to eq("peter@rubyweekly.com")
  end

  it "stores the subject verbatim" do
    message = Newsletter::InboundMessage.new(mail: inbound_mail)

    newsletter = message.save

    expect(newsletter.subject).to eq("Issue 742")
  end

  it "takes the received time from the Date header" do
    sent_at = Time.zone.parse("2026-08-05 09:02:00")
    message = Newsletter::InboundMessage.new(mail: inbound_mail(date: sent_at))

    newsletter = message.save

    expect(newsletter.received_at).to be_within(1.second).of(sent_at)
  end

  it "falls back to the current time when there is no Date header" do
    message = Newsletter::InboundMessage.new(mail: inbound_mail)

    newsletter = message.save

    expect(newsletter.received_at).to be_within(1.minute).of(Time.current)
  end

  it "stores the HTML part as the body" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(html: "<p>Ruby 3.4 is out</p>")
    )

    newsletter = message.save

    expect(newsletter.body_html).to include("<p>Ruby 3.4 is out</p>")
  end

  it "builds the snippet from the plain text part" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(text: "Ruby 3.4 is out and the parser is new")
    )

    newsletter = message.save

    expect(newsletter.snippet).to eq("Ruby 3.4 is out and the parser is new")
  end

  it "builds the snippet from the HTML when there is no plain text part" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(html: "<p>Ruby 3.4 is out</p>")
    )

    newsletter = message.save

    expect(newsletter.snippet).to eq("Ruby 3.4 is out")
  end

  it "truncates a long snippet" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(text: "word " * 100)
    )

    newsletter = message.save

    expect(newsletter.snippet.length).to be <= Newsletter::InboundMessage::SNIPPET_LENGTH
  end

  it "stores the Message-ID" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(message_id: "<issue-742@rubyweekly.com>")
    )

    newsletter = message.save

    expect(newsletter.message_id).to eq("issue-742@rubyweekly.com")
  end

  it "recognises a redelivery instead of storing it twice" do
    identifier = "<issue-742@rubyweekly.com>"
    Newsletter::InboundMessage.new(mail: inbound_mail(message_id: identifier)).save

    Newsletter::InboundMessage.new(
      mail: inbound_mail(message_id: identifier, html: "<p>Edited</p>")
    ).save

    expect(Newsletter.count).to eq(1)
  end

  it "returns the newsletter already stored when a redelivery arrives" do
    identifier = "<issue-742@rubyweekly.com>"
    first = Newsletter::InboundMessage.new(mail: inbound_mail(message_id: identifier)).save

    second = Newsletter::InboundMessage.new(mail: inbound_mail(message_id: identifier)).save

    expect(second).to eq(first)
  end

  it "still stores two newsletters that carry no Message-ID" do
    Newsletter::InboundMessage.new(mail: inbound_mail).save
    Newsletter::InboundMessage.new(mail: inbound_mail).save

    expect(Newsletter.count).to eq(2)
  end

  it "renders a plain-text newsletter as paragraphs" do
    mail = Mail.read_from_string(
      "From: a@b.com\nSubject: s\nContent-Type: text/plain\n\nFirst para\n\nSecond para"
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to eq("<p>First para</p><p>Second para</p>")
  end

  it "builds a snippet for a plain-text newsletter" do
    mail = Mail.read_from_string(
      "From: a@b.com\nSubject: s\nContent-Type: text/plain\n\nRuby 3.4 is out"
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.snippet).to eq("Ruby 3.4 is out")
  end

  it "stores a non-multipart HTML newsletter" do
    mail = Mail.read_from_string(
      "From: a@b.com\nSubject: s\nContent-Type: text/html\n\n<p>Ruby 3.4</p>"
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("<p>Ruby 3.4</p>")
  end

  it "keeps stylesheet rules out of the snippet" do
    style = "<style>body{margin:0;padding:0;-webkit-text-size-adjust:100%}</style>"
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(html: "#{style}<p>Ruby 3.4 is out</p>")
    )

    newsletter = message.save

    expect(newsletter.snippet).to eq("Ruby 3.4 is out")
  end

  it "stores a newsletter whose From header is not an address" do
    mail = Mail.read_from_string("From: Ruby Weekly\nSubject: s\n\nhi")

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.sender_email).to eq("")
  end

  it "stores a newsletter with no From header at all" do
    mail = Mail.read_from_string("Subject: s\n\nhi")

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter).to be_persisted
  end
end
