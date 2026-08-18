# One inbound email the spam gate refused, read back for the pen.
#
# NewslettersMailbox bounces anything Postmark scores at or above 5.0 before a
# Newsletter row exists, so nothing else in the app can see this mail. Action
# Mailbox keeps the raw source until incineration, which makes the gate
# auditable rather than the one silent drop in the pipeline.
#
# Not a link, unlike Subscriptions::Row: there is no page for mail that never
# became a newsletter, and rendering a stranger's refused HTML is the last
# thing this app should offer to do.
class Subscriptions::Bounce
  # A refused email is read off disk and parsed to print two strings, so the
  # list is capped. A spam flood is exactly the moment this section fills up,
  # and it is also the moment the reader is least served by a page that parses
  # four hundred messages to draw itself.
  LIMIT = 20

  # Everything Action Mailbox still holds, newest first. The blob is preloaded
  # because #mail downloads it, and one query per row to find out where to
  # download from would be the N+1 under an N.
  def self.recent
    ActionMailbox::InboundEmail.bounced.with_attached_raw_email
      .where(created_at: retention_days.days.ago..)
      .order(created_at: :desc).limit(LIMIT)
      .map { |inbound_email| new(inbound_email) }
  end

  # Read off Action Mailbox's own retention rather than written down, so the
  # section's empty line cannot promise thirty days after someone shortens
  # incineration to seven.
  def self.retention_days
    ActionMailbox.incinerate_after.in_days.to_i
  end

  def initialize(inbound_email)
    @inbound_email = inbound_email
  end

  # The From on refused mail is the least trustworthy header in the app: it is
  # forged on spam, and often not an address list at all. Read the way ingest
  # reads it, guarding rather than raising — a section that fails on one
  # malformed header is worse than the silence it exists to end.
  def sender
    display_name.presence || address.presence || I18n.t("newsletters.unknown_sender")
  end

  def subject
    mail.subject.to_s
  end

  # When the gate refused it, not the Date the sender claimed. On mail that
  # scored five for spam the Date is as forged as the rest of it, and what the
  # reader is checking is whether their own subscription was eaten this week.
  def freshness
    Newsletter::Age.new(inbound_email.created_at).in_words
  end

  def to_partial_path
    "subscriptions/bounce"
  end

  private

  attr_reader :inbound_email

  def display_name
    return "" unless from.respond_to?(:display_names)

    from.display_names.first.to_s
  end

  # An unparseable From still carries what the sender wrote — "From: Ruby
  # Weekly" reads back as "Ruby Weekly" — which is more than the fallback
  # would say.
  def address
    return from.to_s unless from.respond_to?(:addresses)

    from.addresses.first.to_s
  end

  def from
    mail[:from]
  end

  def mail
    inbound_email.mail
  end
end
