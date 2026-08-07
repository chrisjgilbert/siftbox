class NewslettersMailbox < ApplicationMailbox
  SPAM_THRESHOLD = 5.0

  before_processing :discard_spam

  def process
    Newsletter::InboundMessage.new(mail: mail).save
  end

  private

  # `bounced!` only records the status. Never `bounce_with` — the sender
  # address on spam is forged, so replying would make this a backscatter
  # source.
  def discard_spam
    bounced! if spam?
  end

  def spam?
    spam_score >= SPAM_THRESHOLD
  end

  # Postmark stamps this on inbound mail; absent, `to_f` reads 0.0. Wrapped
  # because the header repeats on anything forwarded through a filter that
  # already ran, and Mail::Header#[] answers an Array when it does.
  def spam_score
    Array.wrap(mail["X-Spam-Score"]).first&.value.to_f
  end
end
