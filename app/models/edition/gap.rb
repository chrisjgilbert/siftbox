# A morning that produced no edition: what it would have covered, and why it
# did not.
#
# The counterpart to an Edition, and between them they account for every
# window the app has closed. That is the point of the class rather than a side
# effect of it — Edition.watermark reads both, so a window is only ever
# reconsidered when nothing considered it the first time.
#
# The PRD used "gap" for the failure this closes: under fixed 07:00→07:00
# ranges "a failed run or an email landing at 07:02 falls into a gap and is
# never covered". That gap was accidental and silent. This one is deliberate
# and written down, which is the whole difference — and the reader is told
# about it rather than left to notice an edition missing.
class Edition::Gap < ApplicationRecord
  # Nothing arrived, which the reader can see for themselves in the archive.
  EMPTY = "empty".freeze

  # Composition was tried and could not answer. The reader is owed a sentence
  # about it, so this is the reason the editions archive draws.
  FAILED = "failed".freeze

  REASONS = [ EMPTY, FAILED ].freeze

  validates :covered_on, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates :window_ended_at, presence: true
  validates :window_started_at, presence: true

  def self.empty(window)
    record(window, EMPTY)
  end

  def self.failed(window, detail)
    record(window, FAILED, detail)
  end

  # What the archive draws. Only the failures: an empty morning is a morning
  # nothing arrived on, and a list of those is a list of quiet days.
  def self.failed_first
    where(reason: FAILED).order(covered_on: :desc)
  end

  # The newest window this has closed. Half of Edition.watermark; the other
  # half is the newest window an edition covered.
  def self.watermark
    maximum(:window_ended_at)
  end

  # Dated through the reader's zone rather than the server's, the way
  # Edition::Window#edition dates an edition, so a gap and the edition it
  # stands in for cannot file under different days.
  #
  # Idempotent per morning, and it has to be: the failure handlers are what
  # call this, so a RecordNotUnique raised here would escape the handler and
  # take the job down without recording the failure it was called to record.
  # A double-fired schedule closes the same morning twice and that is not a
  # new fact.
  #
  # A failure does take over from an empty, though — a morning that found
  # nothing and was then tried again and failed has something to explain after
  # all. Nothing takes over from a failure: the first explanation is the one
  # that describes what actually went wrong.
  def self.record(window, reason, detail = "")
    covered_on = window.ended_at.in_time_zone.to_date
    standing = find_by(covered_on: covered_on)
    return upgraded(standing, reason, detail) if standing

    create!(
      covered_on: covered_on, detail: detail, reason: reason,
      window_ended_at: window.ended_at, window_started_at: window.started_at
    )
  end
  private_class_method :record

  def self.upgraded(gap, reason, detail)
    return gap unless reason == FAILED && gap.empty_window?

    gap.update!(reason: reason, detail: detail)
    gap
  end
  private_class_method :upgraded

  # Named for the window rather than for the record, because `empty?` on an
  # Active Record object already means something else to everyone who reads it.
  def empty_window?
    reason == EMPTY
  end

  def failed?
    reason == FAILED
  end
end
