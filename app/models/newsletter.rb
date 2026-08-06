class Newsletter < ApplicationRecord
  # What a feed row renders. Bodies run to hundreds of kilobytes and the
  # index never touches them.
  FEED_COLUMNS = %i[
    id sender_name sender_email subject snippet received_at read_at
  ].freeze

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
    Newsletter.where("(received_at, id) > (?, ?)", received_at, id)
      .order(received_at: :asc, id: :asc)
      .first
  end

  def older
    Newsletter.where("(received_at, id) < (?, ?)", received_at, id)
      .order(received_at: :desc, id: :desc)
      .first
  end
end
