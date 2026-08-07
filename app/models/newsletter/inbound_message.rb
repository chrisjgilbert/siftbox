# One inbound email, read as a newsletter.
#
# NewslettersMailbox hands the parsed Mail object here rather than doing the
# work itself, the way a controller hands off to a model.
#
# Real newsletter MIME is messier than the spec suggests: headers repeat,
# From is sometimes not an address at all, and plenty of senders still mail
# plain text. Every reader here guards for that, because anything raised
# during processing loses the newsletter — Action Mailbox marks the inbound
# email failed and the raw source is incinerated after 30 days.
class Newsletter::InboundMessage
  include ActiveModel::Model

  SNIPPET_LENGTH = 120

  attr_accessor :mail

  def save
    recorded = already_recorded
    return recorded if recorded

    store
  rescue ActiveRecord::RecordNotUnique
    already_recorded
  end

  private

  # Action Mailbox dedupes on message_id *and* a checksum of the raw source,
  # so a redelivery whose bytes changed on the way — a relay adding a header,
  # a Postmark retry — still arrives here. Recognising it is what makes
  # ingestion idempotent, which the webhook's retry policy needs.
  def already_recorded
    return if message_id.blank?

    Newsletter.find_by(message_id: message_id)
  end

  # Queued after the transaction commits, not inside it: the worker reads
  # the newsletter back from the database, and would find nothing there if
  # it picked the job up first.
  def store
    newsletter = Newsletter.transaction do
      Newsletter.create!(attributes).tap do |stored|
        Newsletter::InlineImages.new(stored, mail.all_parts).attach

        # After InlineImages rather than before: attach rewrites the body's
        # cid: references to app paths, and reading the lead first would
        # store a URL no browser can resolve.
        #
        # Newsletter::RemoteImagesJob captures it again once it has rewritten
        # the hotlinked images too. This one is what the feed shows until
        # then — the sender's own URL, which is where the body still points.
        stored.capture_lead_image
      end
    end

    Newsletter::RemoteImagesJob.perform_later(newsletter)
    newsletter
  end

  def attributes
    {
      message_id: message_id,
      sender_name: sender_name,
      sender_email: sender_email,
      subject: mail.subject.to_s,
      body_html: body_html,
      snippet: snippet,
      received_at: received_at
    }
  end

  def message_id
    mail.message_id.to_s
  end

  # `mail[:from]` is a Mail::UnstructuredField when the header is not a
  # parseable address list ("From: Ruby Weekly"), and nil when it is absent.
  # Neither answers the address methods, and neither is worth losing mail to.
  def from_field
    mail[:from]
  end

  # An unparseable From still carries what the sender wrote — "From: Ruby
  # Weekly" reads back as "Ruby Weekly" — so keep it as the name rather than
  # storing nothing and rendering a nameless row.
  def sender_name
    return "" if from_field.nil?
    return from_field.to_s unless from_field.respond_to?(:display_names)

    from_field.display_names.first.to_s
  end

  def sender_email
    return "" unless from_field.respond_to?(:addresses)

    from_field.addresses.first.to_s
  end

  def received_at
    mail.date&.to_time || Time.current
  end

  def html_source
    return mail.html_part.decoded if mail.html_part
    return mail.decoded if mail.mime_type == "text/html"

    ""
  end

  def text_source
    return mail.text_part.decoded if mail.text_part
    return mail.decoded if mail.mime_type == "text/plain"

    ""
  end

  # A plain-text newsletter still has to render as something. Wrapping its
  # paragraphs is the difference between a readable article and a blank page.
  def body_html
    html_source.presence || paragraphs(text_source)
  end

  def paragraphs(text)
    text.split(/\n{2,}/).map { |line| "<p>#{ERB::Util.html_escape(line.strip)}</p>" }
      .join
  end

  def snippet
    plain_text.truncate(SNIPPET_LENGTH, separator: " ")
  end

  # Newsletter::Body's text, not the raw HTML's: Nokogiri's #text returns the
  # contents of <style> and <script> too, and most newsletters open with a
  # stylesheet longer than the snippet.
  def plain_text
    text_source.presence&.squish || Newsletter::Body.new(html_source).text
  end
end
