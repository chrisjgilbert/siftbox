class Newsletter < ApplicationRecord
  # What a feed row renders. Bodies run to hundreds of kilobytes and the
  # index never touches them.
  FEED_COLUMNS = %i[
    id sender_name sender_email subject snippet received_at
    lead_image_url
  ].freeze

  # What a story's citation renders: the sender's name and a link to the
  # original. Without this an edition of forty citations reads forty full
  # bodies — tens of megabytes — to print forty names. The subject is here
  # because EditionTranscript prints it beside the name when an edition is
  # judged in a terminal.
  CITATION_COLUMNS = %i[id sender_name sender_email subject].freeze

  # What a row of the Subscriptions page renders: who sent it, what they
  # called it, and how long ago it landed.
  PEN_COLUMNS = %i[id sender_name sender_email subject received_at].freeze

  # One row per address: the mail that introduced the sender. A correlated
  # NOT EXISTS rather than a GROUP BY, because the page wants the newsletter
  # itself — the row links to it — and grouping hands back an aggregate that
  # only SQLite would let a bare column ride along with.
  #
  # Ordered on (received_at, id) for the same reason every ordering here is:
  # Date headers carry whole seconds, so a batch send ties, and without the
  # id both tied rows read as earliest and the sender is listed twice.
  #
  # No content carve-out. This is the net for a confirmation the phrase set
  # missed and for a subscription that never arrived, so a sender whose only
  # mail is sitting in the pen is precisely the sender to show.
  EARLIEST_FROM_SENDER = <<~SQL.squish
    NOT EXISTS (
      SELECT 1 FROM newsletters earlier
      WHERE earlier.sender_email = newsletters.sender_email
      AND (earlier.received_at, earlier.id) < (newsletters.received_at, newsletters.id)
    )
  SQL

  has_many_attached :inline_images

  # SQLite stops reading a string literal at a NUL, so one stray byte fails
  # the INSERT and loses the newsletter. Held here rather than where the mail
  # is read, because it is a fact about storing a string and not about
  # reading MIME — Newsletter::InlineImages and Newsletter::RemoteImages both
  # rewrite body_html later without going near the mail reader.
  normalizes :body_html, :sender_email, :sender_name, :snippet, :subject,
    with: ->(value) { value.delete("\0") }

  # Three nullable timestamps allow far more combinations than mean anything,
  # and each meaningless one is a page reading a falsehood: a resolution with
  # no hold lists mail in a pen section it never entered, and a stray
  # released_at drags ordinary content into a second edition window. The
  # absence rule closes a double resolution from either side, because
  # whichever of the two is written second is the one being validated.
  validates :held_at, presence: true, if: :resolved?
  validates :received_at, presence: true
  validates :released_at, absence: true, if: :dismissed?

  # Date headers carry whole seconds, so a batch send lands several
  # newsletters on the same instant. Every ordering here breaks the tie on id
  # so it stays total — otherwise tied rows reorder between page loads and
  # drop out of the newer/older chain.
  def self.newest_first
    order(received_at: :desc, id: :desc)
  end

  def self.oldest_first
    order(received_at: :asc, id: :asc)
  end

  def self.for_citation
    select(CITATION_COLUMNS)
  end

  def self.for_feed
    select(FEED_COLUMNS)
  end

  def self.for_pen
    select(PEN_COLUMNS)
  end

  def self.first_from_sender
    where(EARLIEST_FROM_SENDER)
  end

  def self.without_lead_image
    where(lead_image_url: "")
  end

  # The pen: flagged at ingest and not yet dealt with. Both readers — the
  # Subscriptions page's first section and the edition page's badge — want
  # the unresolved set, so the resolution check lives here rather than in
  # each of them. Not what an edition window excludes: this stops matching
  # mail once it is dismissed, and a window built from it would readmit
  # dismissed confirmations for completeness to force into Briefly. The
  # window wants .content.
  def self.held
    where.not(held_at: nil).where(dismissed_at: nil, released_at: nil)
  end

  def self.released
    where.not(released_at: nil)
  end

  # What the originals archive shows, and the only set an edition is composed
  # from. Admin mail would answer "did Money Stuff arrive?" with a Substack
  # confirmation, so mail in the pen and mail dismissed out of it stays off
  # it entirely, while released mail reads as though it had never been
  # flagged. Stated as a disjunction rather than as a negation of .held,
  # because dismissed mail keeps its held_at and .held has already stopped
  # matching it.
  def self.content
    where(held_at: nil).or(released)
  end

  # Mail the pen has never touched, which is the half of the archive the
  # backfill has anything to say about. Deliberately not .content: released
  # mail carries a held_at too, and re-flagging something the reader has
  # already called a newsletter would be the app arguing with them.
  def self.never_held
    where(held_at: nil)
  end

  # Nothing a published edition has quoted. Holding a cited newsletter hides
  # it from the archive the citation links to, and releasing it later would
  # carry it into a second edition — so the backfill leaves the window an
  # edition covered exactly as it found it.
  #
  # Through .citing_mail rather than the whole table, and it is not a
  # narrowing for tidiness. A citation naming a blog post leaves newsletter_id
  # NULL, and SQL reads `id NOT IN (NULL, 4)` as NULL rather than as true — so
  # one post citation anywhere in the table would answer that no mail is
  # uncited at all, which reads as an ordinary quiet day rather than as a bug.
  def self.uncited
    where.not(id: Edition::Citation.citing_mail.select(:newsletter_id))
  end

  def lead_image?
    lead_image_url.present?
  end

  # Waiting in the pen right now, not "was ever flagged". The badge has to
  # clear the moment the reader deals with a confirmation, and the top bar on
  # the original has to go back to the archive's. The held_at stamp itself
  # survives resolution — that the mail was once flagged is how the archive
  # knows to keep a dismissed confirmation off it.
  def held?
    held_at.present? && !resolved?
  end

  def dismissed?
    dismissed_at.present?
  end

  def released?
    released_at.present?
  end

  # One name for both endings, so nothing downstream has to remember there
  # are two of them.
  def resolved?
    dismissed? || released?
  end

  # Read out of the stored body rather than the raw email, so it works both
  # at ingest and for newsletters stored before the column existed. Safe to
  # run again: the same body gives the same answer.
  def capture_lead_image
    update!(lead_image_url: Newsletter::LeadImage.new(Newsletter::Body.new(body_html)).url)
  end

  # Idempotent because the heuristic gets pointed at stored rows again: the
  # backfill the PRD's backtests need would otherwise re-stamp mail still
  # waiting in the pen, and pull mail the reader already released straight
  # back out of the archive.
  def hold
    return if held_at.present?

    update!(held_at: Time.current)
  end

  # Confirmed, or simply cleared — the two are the same to us. The original
  # renders in a sandboxed frame with an opaque origin, so the app cannot
  # observe the confirm click; this is the reader saying so, and nothing
  # infers it.
  # Idempotent on itself, the way hold is, though the repeat comes from the
  # reader rather than a backfill: the pen row disappears the moment it
  # resolves, so a second dismiss is a stale tab. When the misfire was caught
  # is what the phrase set gets judged against later, and re-stamping would
  # replace that with the moment someone clicked twice. Only the repeat is
  # quiet — dismissing something already released is a contradiction, not a
  # double-click, and the validation still raises on it.
  def dismiss
    return if dismissed?

    update!(dismissed_at: Time.current)
  end

  # The heuristic misfired and this was content all along. Recorded as its
  # own timestamp rather than by clearing held_at, because the next edition's
  # window has to pick the newsletter up on when it was released — its
  # received_at is behind the watermark by then.
  def release
    return if released?

    update!(released_at: Time.current)
  end

  # "" rather than the whole string when there is no @ to split on. Mail
  # parses "From: newsletter" as a one-address list, so sender_email can be a
  # bare local part — and splitting that yields the address back, which the
  # reader's kicker renders as "newsletter / newsletter".
  def sender_domain
    return "" unless sender_email.include?("@")

    sender_email.split("@").last.to_s
  end

  # Where the rewritten image references in body_html point. Written by
  # Newsletter::InlineImages at ingest and Newsletter::RemoteImages just
  # after, then read back by Newsletter::Source — so it has to be built in
  # one place, not three.
  def inline_image_path(blob)
    Rails.application.routes.url_helpers.newsletter_image_path(self, blob)
  end
end
