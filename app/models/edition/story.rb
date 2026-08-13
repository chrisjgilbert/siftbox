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

  belongs_to :edition, touch: true

  validates :body, presence: true
  validates :position, presence: true, uniqueness: { scope: :edition }
  validates :section, presence: true, inclusion: { in: SECTIONS }

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
end
