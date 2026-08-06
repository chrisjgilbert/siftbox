# One inbound email, read as a newsletter.
#
# NewslettersMailbox hands the parsed Mail object here rather than doing the
# work itself, the way a controller hands off to a model.
class Newsletter::InboundMessage
  include ActiveModel::Model

  SNIPPET_LENGTH = 120

  attr_accessor :mail

  def save
    newsletter = Newsletter.create!(
      message_id: message_id,
      sender_name: sender_name,
      sender_email: sender_email,
      subject: mail.subject.to_s,
      body_html: body_html,
      snippet: snippet,
      received_at: received_at
    )

    Newsletter::InlineImages.new(newsletter, mail.attachments).attach
    newsletter
  end

  private

  def message_id
    mail.message_id.to_s
  end

  def sender_name
    mail[:from]&.display_names&.first.to_s
  end

  def sender_email
    mail.from&.first.to_s
  end

  def received_at
    mail.date&.to_time || Time.current
  end

  def body_html
    return mail.html_part.decoded if mail.html_part
    return mail.decoded if mail.mime_type == "text/html"

    ""
  end

  def snippet
    plain_text.truncate(SNIPPET_LENGTH, separator: " ")
  end

  def plain_text
    return mail.text_part.decoded.squish if mail.text_part

    Loofah.html5_fragment(body_html).text.squish
  end
end
