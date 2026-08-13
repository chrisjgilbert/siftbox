# The joint between a story and one of the newsletters it was written from.
# Every claim in an edition traces back through these, which is what makes the
# edition safe to distrust: the original is always one link away.
#
# A real table rather than an array of ids on the story, because RSS items
# later plug in here as a second source type. Nothing polymorphic is being
# built for that now — this only leaves the seam where it goes.
class Edition::Citation < ApplicationRecord
  # Deliberately not touched, against the rule of thumb for belongs_to. Being
  # cited is something the edition did, not something that happened to the
  # newsletter, and touching would rewrite every newsletter in the window each
  # time an edition is composed or regenerated.
  belongs_to :newsletter

  # Rails derives the foreign key from the association name, so :story asks
  # for story_id and the column is edition_story_id. Naming the association
  # edition_story instead would spell Edition twice inside Edition, so the
  # key is stated. Doing that switches off automatic inverse detection, hence
  # inverse_of on both ends — without it, a story built with its citations in
  # memory reloads the story it already has.
  # Not touched either, and for the same reason as the newsletter above rather
  # than a different one. Composition writes an edition once and never again,
  # so there is no staleness for a touch to signal — and touch propagates, so
  # every citation would walk up to the story and on to the edition, rewriting
  # the one edition row once per citation inside a single SQLite write
  # transaction. See the note on immutability in the editions migration.
  belongs_to :story,
    class_name: "Edition::Story",
    foreign_key: :edition_story_id,
    inverse_of: :citations

  # The unique index is what actually holds under a retried composition —
  # this is here so a duplicate reads as a validation failure rather than a
  # RecordNotUnique out of the database.
  validates :newsletter, uniqueness: { scope: :story }
end
