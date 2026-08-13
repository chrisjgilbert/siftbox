# A day's briefing: the stories an AI editor wrote from every newsletter that
# arrived in one window, in the order it wants them read.
#
# Not scoped to a user, for the same reason Feed isn't — one inbound address,
# one account, and the authentication gate is the scope. See README.md on what
# multiple users would take.
class Edition < ApplicationRecord
  # Ordered through Edition::Story's own method rather than an inline order
  # here, so the position ordering has one owner. Declared dependent even
  # though the foreign key already cascades: the constraint is the floor that
  # catches a delete going round Rails, and this is what gives each story its
  # own destroy callbacks on the way out.
  has_many :stories, -> { in_position_order }, dependent: :destroy, inverse_of: :edition

  validate :stories_hold_distinct_positions

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

  # The page renders the three sections separately, but it is one edition's
  # worth of stories either way. Sifted in Ruby off the loaded association
  # rather than asked for in three queries: Relation#select takes a block, so
  # the ordered association loads once and all three readers partition that
  # same load.
  def lead_stories
    stories.select(&:lead?)
  end

  def briefly
    stories.select(&:briefly?)
  end

  def reading_list
    stories.select(&:reading_list?)
  end

  # The reading list is the one section that disappears when it is empty: a
  # window with no evergreen items renders no heading at all, rather than a
  # heading over nothing.
  def reading_list?
    reading_list.any?
  end

  private

  # The same blind spot Edition::Story has about its citations: Story's own
  # uniqueness validation reads the table, so two unsaved stories claiming
  # position 3 both pass it and the insert fails on the index instead, under
  # a message that names no position.
  #
  # Read off the association's in-memory target rather than through #stories,
  # which would load it. Validating on create would then cache an empty
  # collection, and every section reader after that would answer out of that
  # cache — an edition full of stories rendering as an edition of none.
  def stories_hold_distinct_positions
    claimed = association(:stories).target.map(&:position)
    return if claimed.length == claimed.uniq.length

    errors.add(:stories, :duplicate_position)
  end
end
