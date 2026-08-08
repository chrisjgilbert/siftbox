class Newsletter < ApplicationRecord
  # What a feed row renders. Bodies run to hundreds of kilobytes and the
  # index never touches them.
  FEED_COLUMNS = %i[
    id sender_name sender_email subject snippet received_at read_at
    lead_image_url
  ].freeze

  # What the reader's previous/next links render. Without this the two
  # neighbour lookups pull a full body_html each, to show a sender and a
  # subject.
  NEIGHBOUR_COLUMNS = %i[id sender_name sender_email subject received_at].freeze

  has_many_attached :inline_images

  # SQLite stops reading a string literal at a NUL, so one stray byte fails
  # the INSERT and loses the newsletter. Held here rather than where the mail
  # is read, because it is a fact about storing a string and not about
  # reading MIME — Newsletter::InlineImages and Newsletter::RemoteImages both
  # rewrite body_html later without going near the mail reader.
  normalizes :body_html, :sender_email, :sender_name, :snippet, :subject,
    with: ->(value) { value.delete("\0") }

  validates :received_at, presence: true

  # Date headers carry whole seconds, so a batch send lands several
  # newsletters on the same instant. Every ordering here breaks the tie on id
  # so it stays total — otherwise tied rows reorder between page loads and
  # drop out of the newer/older chain.
  def self.newest_first
    order(received_at: :desc, id: :desc)
  end

  def self.oldest_first
    order(received_at: :asc, id: :asc)
  end

  def self.for_feed
    select(FEED_COLUMNS)
  end

  def self.neighbour
    select(NEIGHBOUR_COLUMNS)
  end

  def self.unread
    where(read_at: nil)
  end

  def self.without_lead_image
    where(lead_image_url: "")
  end

  def read?
    read_at.present?
  end

  def lead_image?
    lead_image_url.present?
  end

  # Read out of the stored body rather than the raw email, so it works both
  # at ingest and for newsletters stored before the column existed. Safe to
  # run again: the same body gives the same answer.
  def capture_lead_image
    update!(lead_image_url: Newsletter::LeadImage.new(Newsletter::Body.new(body_html)).url)
  end

  def mark_read
    return if read?

    update!(read_at: Time.current)
  end

  def mark_unread
    update!(read_at: nil)
  end

  # "" rather than the whole string when there is no @ to split on. Mail
  # parses "From: newsletter" as a one-address list, so sender_email can be a
  # bare local part — and splitting that yields the address back, which the
  # reader's kicker renders as "newsletter / newsletter".
  def sender_domain
    return "" unless sender_email.include?("@")

    sender_email.split("@").last.to_s
  end

  # Ordered through the scopes rather than inline, so the tie-break on id has
  # one owner. Stated in three places it would drift, and the chain silently
  # dropping a newsletter is exactly what the tie-break exists to prevent.
  def newer
    Newsletter.neighbour.oldest_first
      .where("(received_at, id) > (?, ?)", received_at, id)
      .first
  end

  def older
    Newsletter.neighbour.newest_first
      .where("(received_at, id) < (?, ?)", received_at, id)
      .first
  end

  # Where the rewritten image references in body_html point. Written by
  # Newsletter::InlineImages at ingest and Newsletter::RemoteImages just
  # after, then read back by Newsletter::Source — so it has to be built in
  # one place, not three.
  def inline_image_path(blob)
    Rails.application.routes.url_helpers.newsletter_image_path(self, blob)
  end
end
