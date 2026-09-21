# A day's briefing: the stories an AI editor wrote from every newsletter that
# arrived in one window, in the order it wants them read.
#
# Not scoped to a user, for the same reason Feed isn't — one inbound address,
# one account, and the authentication gate is the scope. See docs/operating.md
# on what multiple users would take.
class Edition < ApplicationRecord
  # What a line of the archive renders. raw_response holds the model's whole
  # answer — the stories, their citations and the prose, as JSON — so a year
  # of mastheads reads megabytes without this. The house pattern is
  # Newsletter::FEED_COLUMNS.
  ARCHIVE_COLUMNS = %i[id number published_on].freeze

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

  def self.for_archive
    select(ARCHIVE_COLUMNS)
  end

  # What the page renders, loaded flat. The section readers below partition
  # one load of the stories, but each story's citations would still fire a
  # query of their own on first touch — a query per story on a page that draws
  # every story there is. Preloading keeps the in_position_order scope on the
  # association and costs the same handful of queries whatever the edition's
  # size.
  # Both kinds of citation, and a post's blog with them: the page prints the
  # blog's name under every post it cited, so without the innermost preload an
  # edition citing six posts reads six blogs one at a time.
  def self.for_reading
    includes(stories: [ { blog_posts: :blog }, :newsletters ])
  end

  # The high-water mark the next window starts from, and nil before anything
  # has been covered — the floor for that one is Edition::Window's to choose,
  # because it is the thing that knows when composition started.
  #
  # Read across editions *and* gaps, because what it marks is the newest
  # window that has been considered rather than the newest one that produced
  # something. A morning that found nothing, or that failed, has been
  # accounted for, and reconsidering it is what aims a multi-day window at a
  # token ceiling it cannot clear. See Edition::Gap.
  #
  # maximum rather than latest.window_ended_at: newest_first sorts by the day
  # covered, so an edition backfilled for an earlier day would sit at the top
  # with a cutoff weeks behind the real one, and the next window would
  # re-compose everything since. This is what index_editions_on_window_ended_at
  # is for.
  def self.watermark
    [ maximum(:window_ended_at), Edition::Gap.watermark ].compact.max
  end

  # Numbering follows composition order rather than the day covered. Under a
  # watermark the two agree: a missed day does not leave a gap, it makes the
  # next window bigger, so editions can only be composed in date order in
  # normal operation. They diverge only under a manual backfill, which takes
  # the next number and sorts below the day that beat it out.
  #
  # Read and written in two statements, so two runs at once allocate the same
  # number and the second insert fails on the unique index — a
  # ActiveRecord::RecordNotUnique rather than two editions numbered 4.
  # Whatever composes has to be ready to see it.
  def self.next_number
    maximum(:number).to_i + 1
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
