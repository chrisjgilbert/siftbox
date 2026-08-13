# One item in an edition: a lead story, a Briefly line, or a reading list
# entry. All three are the same shape at different lengths and registers, so
# the section is a column rather than three classes.
class Edition::Story < ApplicationRecord
  LEAD = "lead".freeze
  BRIEFLY = "briefly".freeze
  READING_LIST = "reading_list".freeze

  # Stored as the word rather than an integer enum: the raw table gets read by
  # hand while the prompt is being iterated, and an integer means nothing
  # there.
  SECTIONS = [ LEAD, BRIEFLY, READING_LIST ].freeze

  # Deliberately not touched, against the rule of thumb for belongs_to: an
  # edition is written once at composition and immutable after, so a bumped
  # updated_at would only ever record the edition finishing being built.
  belongs_to :edition

  # Same foreign key mismatch as on the other end of the citation: the column
  # is edition_story_id, and Rails demodulises Edition::Story down to story_id
  # when it guesses.
  has_many :citations, foreign_key: :edition_story_id, dependent: :destroy, inverse_of: :story
  has_many :newsletters, through: :citations

  validates :body, presence: true
  validates :position, presence: true, uniqueness: { scope: :edition }
  validates :section, presence: true, inclusion: { in: SECTIONS }

  validate :citations_point_at_distinct_newsletters

  # Position is unique within an edition, so this is already a total order and
  # needs no tie-break on id.
  def self.in_position_order
    order(:position)
  end

  def lead?
    section == LEAD
  end

  def briefly?
    section == BRIEFLY
  end

  def reading_list?
    section == READING_LIST
  end

  private

  # Citation's own uniqueness validation and the unique index behind it both
  # answer from what is already in the table, so neither sees a story citing
  # one newsletter twice in a graph that has not been saved yet — which is
  # the exact shape composition builds, out of model output that is perfectly
  # capable of naming the same source twice in one story. Without this the
  # insert fails on the index and Rails reports "Stories is invalid", naming
  # neither the story nor the newsletter.
  # In-memory target rather than #citations, which would load the association
  # and leave a validated story answering out of a stale cache.
  def citations_point_at_distinct_newsletters
    cited = association(:citations).target.map(&:newsletter_id)
    return if cited.length == cited.uniq.length

    errors.add(:citations, :duplicate_newsletter)
  end
end
