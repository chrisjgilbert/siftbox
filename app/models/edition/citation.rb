# The joint between a story and one of the newsletters it was written from.
# Every claim in an edition traces back through these, which is what makes the
# edition safe to distrust: the original is always one link away.
#
# A real table rather than an array of ids on the story, which is what lets a
# blog post plug in beside a newsletter as a second source type without the
# story knowing there are two.
#
# One row names exactly one of them, and the database says so. Two nullable
# foreign keys under a check constraint rather than a polymorphic pair,
# because a type string and an untyped integer are a pointer nothing can
# constrain; see docs/blogs-rss.md.
class Edition::Citation < ApplicationRecord
  # Optional in the ActiveRecord sense only. A citation still has to name a
  # source — that is #names_one_source below and the check constraint behind
  # it — but which of the two columns carries it is not something belongs_to
  # can express.
  #
  # Deliberately not touched, against the rule of thumb for belongs_to. Being
  # cited is something the edition did, not something that happened to the
  # newsletter, and touching would rewrite every newsletter in the window each
  # time an edition is composed or regenerated.
  belongs_to :newsletter, optional: true

  # Class name stated because Rails would look for a top-level BlogPost, and
  # the foreign key is already blog_post_id from the reference, so only the
  # class needs saying.
  belongs_to :blog_post, class_name: "Blog::Post", optional: true

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

  # The unique indexes are what actually hold under a retried composition —
  # these are here so a duplicate reads as a validation failure rather than a
  # RecordNotUnique out of the database.
  #
  # allow_nil on both, because a story citing three posts has three rows with
  # a NULL newsletter_id and they are not duplicates of each other. SQLite's
  # indexes already count NULLs as distinct; this is the validation agreeing
  # with them rather than refusing the second post citation on its own.
  validates :blog_post, uniqueness: { scope: :story }, allow_nil: true
  validates :newsletter, uniqueness: { scope: :story }, allow_nil: true

  validate :names_one_source

  # The citations that name mail, which is not all of them any more. Anything
  # asking "which newsletters has an edition quoted" has to say this, because
  # a post's citation leaves newsletter_id NULL and a NULL inside a NOT IN
  # makes the whole comparison NULL — see Newsletter.uncited.
  def self.citing_mail
    where.not(newsletter_id: nil)
  end

  private

  # What the check constraint says, said early enough to name the field. The
  # constraint is the guarantee — it holds against a console, a migration, or
  # code that has not been written yet — and this is so the ordinary path
  # fails as a validation rather than as a StatementInvalid out of SQLite,
  # which names the constraint and not the row.
  def names_one_source
    return if newsletter.present? ^ blog_post.present?

    errors.add(:base, :one_source)
  end
end
