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
  def spam_score
    mail["X-Spam-Score"]&.value.to_f
  end
end
