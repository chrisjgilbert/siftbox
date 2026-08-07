class Newsletter < ApplicationRecord
  # What a feed row renders. Bodies run to hundreds of kilobytes and the
  # index never touches them.
  FEED_COLUMNS = %i[
    id sender_name sender_email subject snippet received_at read_at
  ].freeze

  # What the reader's previous/next links render. Without this the two
  # neighbour lookups pull a full body_html each, to show a sender and a
  # subject.
  NEIGHBOUR_COLUMNS = %i[id sender_name sender_email subject received_at].freeze

  has_many_attached :inline_images

  validates :received_at, presence: true

  # Date headers carry whole seconds, so a batch send lands several
  # newsletters on the same instant. Every ordering here breaks the tie on id
  # so it stays total — otherwise tied rows reorder between page loads and
  # drop out of the newer/older chain.
  def self.newest_first
    order(received_at: :desc, id: :desc)
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

  def read?
    read_at.present?
  end

  def mark_read
    return if read?

    update!(read_at: Time.current)
  end

  def mark_unread
    update!(read_at: nil)
  end

  def sender_domain
    sender_email.split("@").last.to_s
  end

  def newer
    Newsletter.neighbour.where("(received_at, id) > (?, ?)", received_at, id)
      .order(received_at: :asc, id: :asc)
      .first
  end

  def older
    Newsletter.neighbour.where("(received_at, id) < (?, ?)", received_at, id)
      .order(received_at: :desc, id: :desc)
      .first
  end

  # Where the rewritten cid: references in body_html point. Written by
  # Newsletter::InlineImages at ingest and read back by Newsletter::Source,
  # so it has to be built in one place, not two.
  def inline_image_path(blob)
    Rails.application.routes.url_helpers.newsletter_image_path(self, blob)
  end
end
