class NewslettersMailbox < ApplicationMailbox
  SPAM_THRESHOLD = 5.0

  before_processing :discard_spam

  def process
    Newsletter::InboundMessage.new(mail: mail).save
  end

  private

  # Marked delivered rather than bounced: a bounce would be sent to the forged
  # sender address on the spam, making this app a backscatter source. Setting
  # the status is what halts the callback chain — see ActionMailbox::Base.
  def discard_spam
    delivered! if spam?
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
