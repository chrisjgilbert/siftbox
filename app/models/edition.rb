# A day's briefing: the stories an AI editor wrote from every newsletter that
# arrived in one window, in the order it wants them read.
#
# Not scoped to a user, for the same reason Feed isn't — one inbound address,
# one account, and the authentication gate is the scope. See README.md on what
# multiple users would take.
class Edition < ApplicationRecord
  validates :number, presence: true, uniqueness: true
  validates :published_at, presence: true
  validates :published_on, presence: true, uniqueness: true
  validates :window_ended_at, presence: true
  validates :window_started_at, presence: true

  # By the day covered, never by published_at. A run that fails at 07:00 and
  # retries the next morning still publishes the earlier day's edition, and
  # ordering by the wall clock would file it above the day that beat it out.
  # published_on is unique, so this ordering is already total and needs no
  # tie-break on id the way Newsletter's does.
  def self.newest_first
    order(published_on: :desc)
  end

  def self.latest
    newest_first.first
  end
end
