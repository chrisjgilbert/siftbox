# An edition read aloud: the audio, and what happened while it was being made.
#
# Made on demand rather than every morning. Composition costs the same whether
# anybody reads the edition or not, but a recording nobody plays is money for
# nothing — so nothing is recorded until a reader presses play, and once
# recorded it is kept, because a second listen should cost nothing and the
# archive is the app's memory.
#
# Three timestamps rather than a status column, per .claude/rules/database.md.
# They are read as three questions the page asks in order: is it ready, did it
# fail, or is it still being made.
class Edition::Recording < ApplicationRecord
  # What the vendor sends and what the controller serves, read off the voice
  # rather than spelled again here: the voice checks what came back, this
  # stamps what is stored, and two literals that must match is a pair that can
  # drift.
  AUDIO_TYPE = Edition::Voice::CONTENT_TYPE

  # Deliberately not touched, for the reason Edition::Story gives: an edition
  # is written once at composition and immutable after, and a recording made
  # weeks later would otherwise bump the edition's updated_at to say so.
  belongs_to :edition

  # The blob goes when the row goes, which is Active Storage's own default for
  # has_one_attached and is what the migration's cascade assumes.
  has_one_attached :audio

  validates :edition, uniqueness: true
  validates :requested_at, presence: true

  # A reader has asked to hear this edition, which is not the same as a reader
  # having tapped a button: a double tap on a phone, a back button, a retried
  # Turbo submission and a stale tab all arrive here, and each synthesis is a
  # paid request. So anything already in hand is answered with rather than
  # asked for again — a recording being made will arrive on its own, and one
  # already made is what the reader wanted.
  #
  # The job is enqueued here rather than in the controller, the way
  # Blog::Subscription and Newsletter::InboundMessage enqueue theirs: the
  # controller's job is to answer the request, and what asking for a recording
  # involves is this class's to know.
  #
  # What does start a job: no recording at all, one that failed, and one that
  # has been pending longer than a job can run, which is the worker having died
  # with the row still saying it was working.
  #
  # The rescue is the backstop under the index for two callers arriving in the
  # same instant, where both find no row and both pass the uniqueness
  # validation before either inserts. The loser sees RecordInvalid if the
  # winner committed before its own validation read the table and
  # RecordNotUnique if it did not, so both are caught — and re-raised unless a
  # row really is there now, because a validation failing for any other reason
  # is a bug rather than a race.
  def self.start(edition)
    found = find_by(edition: edition)
    return found if found&.ready? || found&.pending?

    asked(found || new(edition: edition))
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    won = find_by(edition: edition)
    raise if won.nil?

    won
  end

  # Stamped and handed to the queue. Separate from .start so that reads the way
  # it decides — what is in hand, or ask for one — rather than mixing the
  # decision with the asking.
  def self.asked(recording)
    recording.update!(requested_at: Time.current, failed_at: nil)
    Edition::RecordingJob.perform_later(recording)

    recording
  end

  # One transaction over the two writes, per .claude/rules/database.md. They
  # are two commits otherwise — Active Storage saves the attachment against an
  # already-persisted record the moment it is attached — so a failure between
  # them would leave audio stored and paid for behind a row that never says it
  # is ready, which is the stuck state #pending?'s two clauses exist to end and
  # no reason to enter one.
  #
  # Both stamps in one update: a retry that works has to clear the failure as
  # well as record the success, or the page would draw a player and offer to
  # make it again underneath.
  def store(bytes, voice:)
    transaction do
      audio.attach(io: StringIO.new(bytes), filename: filename, content_type: AUDIO_TYPE)
      update!(voice: voice, completed_at: Time.current, failed_at: nil)
    end
  end

  def abandon
    update!(failed_at: Time.current)
  end

  # The stamp and the blob, not the stamp alone. A purged blob leaves the
  # completion behind, and a page that trusted the stamp would draw a player
  # with no source in it.
  def ready?
    completed_at.present? && audio.attached?
  end

  def failed?
    failed_at.present?
  end

  # Two clauses, and they answer different failures. completed_at is the first:
  # a recording that came back is not still being made, whatever became of its
  # audio afterwards — so a purged blob falls straight through to the button
  # rather than being called pending and waiting out a clock to correct it.
  #
  # The clock is the second, and it covers only what it can: a job that never
  # ran at all. The job stamps a failure for anything that goes wrong while it
  # is running, but a killed worker or a stopped queue stamps nothing, and
  # without a bound that row says "still being made" for ever.
  #
  # The bound is the job's own worst case rather than a number chosen here.
  # Asked at call time rather than held as a constant, so nothing loads in a
  # particular order to make it true.
  def pending?
    return false if failed? || completed_at.present?

    requested_at > Edition::RecordingJob::LONGEST_RUN.ago
  end

  private

  # What a reader gets if they save the file, so it names the edition rather
  # than the row.
  def filename
    "edition-#{edition.number}.#{Edition::Voice::EXTENSION}"
  end
end
