class NewslettersMailbox < ApplicationMailbox
  SPAM_THRESHOLD = 5.0

  before_processing :discard_spam

  def process
    Newsletter::InboundMessage.new(mail: mail).save
  end

  private

  # `bounced!`, which ActionMailbox::Base documents as the way to halt
  # processing, records the rejection without sending anything — only
  # `bounce_with` delivers a message, and bouncing to the forged sender on
  # spam would make this app a backscatter source.
  #
  # It also keeps spam distinguishable in the conductor: discarded mail reads
  # as bounced rather than sitting among the newsletters marked delivered.
  def discard_spam
    bounced! if spam?
  end

  def spam?
    spam_score >= SPAM_THRESHOLD
  end

  # Postmark stamps this on inbound mail. Absent, `to_f` reads 0.0.
  #
  # Mail::Header#[] returns an Array when a header repeats, which it does on
  # anything forwarded through a mailbox that already ran a spam filter — so
  # `&.value` on the result would raise and lose the newsletter.
  def spam_score
    field = mail["X-Spam-Score"]
    field = field.first if field.is_a?(Array)

    field&.value.to_f
  end
end
