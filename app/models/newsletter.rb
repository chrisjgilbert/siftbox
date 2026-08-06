class Newsletter < ApplicationRecord
  has_many_attached :inline_images

  validates :received_at, presence: true

  def self.newest_first
    order(received_at: :desc)
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
    Newsletter.where("received_at > ?", received_at)
      .order(received_at: :asc)
      .first
  end

  def older
    Newsletter.where("received_at < ?", received_at)
      .order(received_at: :desc)
      .first
  end
end
