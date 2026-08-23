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

    expect(newsletter.snippet.length).to be <= Newsletter::Body::SNIPPET_LENGTH
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

  it "holds a confirmation from a first-time sender" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(from: "no-reply@substack.com", subject: "Confirm your subscription")
    )

    newsletter = message.save

    expect(newsletter.reload).to be_held
  end

  it "leaves an ordinary newsletter out of the pen" do
    message = Newsletter::InboundMessage.new(mail: inbound_mail)

    newsletter = message.save

    expect(newsletter.reload).not_to be_held
  end

  # The guard is asked after the insert, and the newsletter must not count as
  # its own established sender.
  it "leaves confirmation-shaped mail from an established sender out of the pen" do
    create(:newsletter, sender_email: "peter@rubyweekly.com", received_at: 3.days.ago)
    message = Newsletter::InboundMessage.new(mail: inbound_mail(subject: "Confirmation bias"))

    newsletter = message.save

    expect(newsletter.reload).not_to be_held
  end

  it "queues the remote image download after storing" do
    message = Newsletter::InboundMessage.new(mail: inbound_mail)

    expect { message.save }
      .to have_enqueued_job(RemoteImagesJob)
  end

  it "queues no download again for a redelivery" do
    identifier = "<issue-742@rubyweekly.com>"
    Newsletter::InboundMessage.new(mail: inbound_mail(message_id: identifier)).save

    expect {
      Newsletter::InboundMessage.new(
        mail: inbound_mail(message_id: identifier)
      ).save
    }.not_to have_enqueued_job(RemoteImagesJob)
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

  # The address is unrecoverable, but what the sender wrote is not.
  it "keeps an unparseable From as the sender name" do
    mail = Mail.read_from_string("From: Ruby Weekly\nSubject: s\n\nhi")

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.sender_name).to eq("Ruby Weekly")
  end

  it "stores a newsletter with no From header at all" do
    mail = Mail.read_from_string("Subject: s\n\nhi")

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter).to be_persisted
  end

  it "stores the first image in the body as the lead image" do
    mail = inbound_mail(html: %(<p>Hi</p><img src="https://cdn.example/hero.png">))

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.lead_image_url).to eq("https://cdn.example/hero.png")
  end

  it "stores no lead image for a newsletter that carries none" do
    newsletter = Newsletter::InboundMessage.new(mail: inbound_mail).save

    expect(newsletter.lead_image_url).to eq("")
  end

  # Extraction runs after Newsletter::InlineImages, which rewrites cid:
  # references to app paths. Run it first and the column holds a cid: URL
  # that no browser can resolve.
  it "stores an inline image as the lead once its reference is rewritten" do
    mail = Mail.new(from: "peter@rubyweekly.com", subject: "Issue 742") do
      html_part do
        content_type "text/html; charset=UTF-8"
        body %(<img src="cid:hero@rubyweekly">)
      end

      add_file(filename: "hero.png", content: "png-bytes")
    end
    mail.parts.last.content_id = "<hero@rubyweekly>"

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.lead_image_url).to start_with("/newsletters/")
  end

  # Mail raises on a Content-Transfer-Encoding it does not recognise, and
  # anything raised here loses the newsletter for good — Action Mailbox marks
  # the inbound email failed and incinerates the raw source after 30 days.
  it "stores a newsletter whose part declares an unknown transfer encoding" do
    mail = inbound_mail(html: "<p>Ruby 3.4 is out</p>")
    mail.html_part.content_transfer_encoding = "bogus-encoding"

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("Ruby 3.4 is out")
  end

  it "stores a plain-text newsletter whose part declares an unknown transfer encoding" do
    mail = Mail.read_from_string(
      "From: a@b.com\r\nSubject: s\r\nContent-Type: text/plain\r\n" \
      "Content-Transfer-Encoding: bogus-encoding\r\n\r\nRuby 3.4 is out"
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("Ruby 3.4 is out")
  end

  # Mail has nothing to transcode from when a part declares no charset, so it
  # hands back ASCII-8BIT and one Windows-1252 curly quote fails the INSERT.
  # Senders omit the charset constantly, which makes this the likeliest way to
  # lose a newsletter outright.
  it "stores a newsletter whose part declares no charset" do
    mail = Mail.read_from_string(
      "From: a@b.com\r\nSubject: s\r\nContent-Type: text/html\r\n\r\n" \
      "<p>Caf\xE9 news</p>".b
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("Café news")
  end

  it "reads an undeclared part that is already UTF-8 as UTF-8" do
    mail = Mail.read_from_string(
      "From: a@b.com\r\nSubject: s\r\nContent-Type: text/html\r\n\r\n" \
      "<p>Café news</p>".dup.force_encoding(Encoding::BINARY)
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("Café news")
  end

  # SQLite stops reading a string literal at a NUL byte, so one stray byte
  # fails the INSERT and takes the newsletter with it.
  it "stores a newsletter whose body carries a null byte" do
    message = Newsletter::InboundMessage.new(
      mail: inbound_mail(html: "<p>Ruby 3.4#{0.chr} is out</p>")
    )

    newsletter = message.save

    expect(newsletter.body_html).to include("Ruby 3.4 is out")
  end

  # The body reader survives an unknown transfer encoding, but the same
  # header on an inline image part raised out of Newsletter::InlineImages and
  # took the newsletter with it — text, subject, and all.
  it "stores a newsletter whose inline image declares an unknown transfer encoding" do
    mail = Mail.read_from_string(
      "From: a@b.com\r\nSubject: s\r\n" \
      "Content-Type: multipart/related; boundary=X\r\n\r\n--X\r\n" \
      "Content-Type: text/html\r\n\r\n<p>Ruby 3.4 is out</p>" \
      "<img src=\"cid:logo@b.com\">\r\n--X\r\n" \
      "Content-Type: image/png\r\nContent-ID: <logo@b.com>\r\n" \
      "Content-Disposition: inline\r\n" \
      "Content-Transfer-Encoding: bogus-encoding\r\n\r\naGk=\r\n--X--\r\n"
    )

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("Ruby 3.4 is out")
  end

  # tidy_bytes recodes only the runs that are not already UTF-8, so a body
  # that is valid apart from one stray byte keeps the accents it got right.
  # Transcoding the whole string from Windows-1252 would mojibake them.
  it "repairs one stray byte without mangling the rest of the body" do
    headers = "From: a@b.com\r\nSubject: s\r\nContent-Type: text/html\r\n\r\n"
    body = "<p>caf\xC3\xA9 and \xE9</p>".b
    mail = Mail.read_from_string(headers + body)

    newsletter = Newsletter::InboundMessage.new(mail: mail).save

    expect(newsletter.body_html).to include("café and é")
  end
end
