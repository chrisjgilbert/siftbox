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
  # Scoped to the columns a citation is drawn from, the way the feed and the
  # pen are. Unscoped this selects newsletters.*, and an edition's
  # citations then read every cited body in full to print a list of senders.
  has_many :newsletters, -> { for_citation }, through: :citations
  # The second source type, reached the same way and scoped the same way. A
  # story cites mail, posts, or both, and the page draws them as one list.
  has_many :blog_posts, -> { for_citation }, through: :citations

  validates :body, presence: true
  validates :position, presence: true, uniqueness: { scope: :edition }
  validates :section, presence: true, inclusion: { in: SECTIONS }

  validate :citations_point_at_distinct_blog_posts
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

  # Citation's own uniqueness validation and the unique indexes behind it both
  # answer from what is already in the table, so neither sees a story citing
  # one source twice in a graph that has not been saved yet — which is the
  # exact shape composition builds, out of model output that is perfectly
  # capable of naming the same source twice in one story. Without these the
  # insert fails on the index and Rails reports "Stories is invalid", naming
  # neither the story nor the source.
  def citations_point_at_distinct_blog_posts
    return if cites_distinct?(:blog_post_id)

    errors.add(:citations, :duplicate_blog_post)
  end

  def citations_point_at_distinct_newsletters
    return if cites_distinct?(:newsletter_id)

    errors.add(:citations, :duplicate_newsletter)
  end

  # Compacted, and that is the whole reason this is one column at a time
  # rather than a check that the citations are distinct rows. Every post
  # citation leaves newsletter_id nil and every mail citation leaves
  # blog_post_id nil, so a story citing one newsletter and two posts carries
  # two nil newsletter_ids — which is not a newsletter named twice.
  #
  # In-memory target rather than #citations, which would load the association
  # and leave a validated story answering out of a stale cache.
  def cites_distinct?(key)
    cited = association(:citations).target.map(&key).compact

    cited.length == cited.uniq.length
  end
end
