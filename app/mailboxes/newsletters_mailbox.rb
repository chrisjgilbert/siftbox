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

  # Postmark stamps this on inbound mail; absent, `max` is nil and `to_f`
  # reads 0.0. Wrapped because the header repeats on anything forwarded
  # through a filter that already ran, and Mail::Header#[] answers an Array
  # when it does — take the worst score rather than whichever arrived first,
  # or an earlier relay's clean verdict masks the later spam one.
  def spam_score
    Array.wrap(mail["X-Spam-Score"]).map { |field| field.value.to_f }.max.to_f
  end
end
