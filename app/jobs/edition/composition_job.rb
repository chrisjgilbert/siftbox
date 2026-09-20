# The morning's edition, composed out of everything that has become the
# reader's to read since the last one closed. Scheduled for 07:00 Europe/London
# in config/recurring.yml — a Solid Queue recurring task, which is a deploy
# step and is written down as one in docs/deploying.md.
#
# A job rather than anything in the request path, per the PRD: composition
# takes minutes and costs real money, and a reader arriving mid-morning is
# meant to see the last published edition rather than a spinner.
#
# The clock is read here, once, and handed to the window, so the query's top
# bound, the recorded window and the publication time are the same instant. It
# is read at the moment the job runs rather than at the moment it was due,
# because a recurring task has no way to pass its scheduled time in — and
# because under a watermark the two agree anyway: a run that happens late
# covers a window that is correspondingly bigger, and nothing falls between.
class Edition::CompositionJob < ApplicationJob
  # Four goes at the whole job, not to be confused with
  # Edition::Editor::ATTEMPTS, which is three requests to the model inside one
  # of them. Bounded, and the bound is the point: an outage that outlasts the
  # first hour of the morning has already cost the reader the edition they
  # would have read at breakfast, and tomorrow's window covers today's mail
  # regardless. Retrying into the afternoon buys a stale edition nobody asked
  # for and a job that is still trying when the next one starts.
  ATTEMPTS = 4

  # Long enough for a rate limit to clear or a blip to pass. The SDK has
  # already retried the request itself with its own backoff by the time
  # anything reaches here, so these are minutes apart rather than seconds:
  # four runs spaced this far cover three quarters of an hour.
  WAIT = 15.minutes

  # The one failure that waiting fixes. Everything else below is discarded,
  # because a second attempt would ask the same question of the same window
  # and get the same answer back. Once the attempts are spent the block runs
  # and the morning is written down as a gap — three quarters of an hour of
  # retrying is the app having tried sufficiently, and what is owed after that
  # is an explanation rather than another attempt.
  retry_on Edition::Draft::Unavailable, wait: WAIT, attempts: ATTEMPTS do |job, error|
    job.abandon(error)
  end

  # Three full-price requests have already been spent on this window against
  # an unchanged prompt, and the editor has already logged what went uncited.
  # A fourth, fifth and sixth would fail the same way.
  #
  # This morning's sources are not lost, but they will not be reported either:
  # the gap closes the window, so tomorrow covers a day rather than two. That
  # is deliberate. A window that grows with every failure aims a multi-day
  # prompt at a ceiling it cannot clear — at the PRD's own envelope of ~60k
  # input tokens a day, three days is past a 200k context — so the old promise
  # of a bigger window tomorrow degraded into a truncation and no edition at
  # all, silently. The archive lists the gap instead, and the originals are
  # still there to read.
  discard_on(Edition::Editor::Incomplete) do |job, error|
    job.abandon(error, "no edition composed, and not retried")
  end

  # Three different owners, one response. A refusal is a classifier's decision
  # about this window's contents and it will decide the same way again; a
  # truncation is this window against MAX_TOKENS and tomorrow's window is
  # bigger, so it wants a person rather than another go; a rejection is our own
  # bug — a bad schema, a missing key, a model that is not there — and it is
  # fixed by a deploy, not by waiting. None of them is retried and all of them
  # are loud.
  #
  # Named one by one rather than caught as Edition::Draft::Error, for two
  # reasons: the parent would also swallow Unavailable unless the declaration
  # order above happened to be right, and correctness that depends on which
  # rescue was declared last is a trap. And Edition::Draft::Error itself is
  # raised for a response shape nobody has seen — an answer with no text block
  # at all — which should reach the failed queue rather than be handled by a
  # rule written before it existed.
  discard_on(
    Edition::Draft::Refused, Edition::Draft::Truncated, Edition::Draft::Rejected
  ) do |job, error|
    job.abandon(error)
  end

  # Two runs at once both read Edition.next_number before either writes, and
  # the unique indexes on number and published_on reject the second insert.
  # That is the index doing its job, and the run that lost the race has
  # nothing left to do: the day has its edition. Discarded rather than
  # retried, because retrying is how one lost race becomes a storm.
  #
  # Only the concurrent case arrives here. A run starting after another has
  # committed finds the watermark moved and skips on an empty window instead,
  # long before it spends anything — and if mail landed in between, the
  # uniqueness validation catches it first and raises RecordInvalid, which is
  # deliberately not rescued: a story with a section the model invented raises
  # the same thing, and that must not be swallowed.
  discard_on(ActiveRecord::RecordNotUnique) do
    Rails.logger.info("another run has already published today's edition")
  end

  def perform
    return skipped if window.empty?

    Edition::Editor.new(window.edition, window.sources).compose
  end

  # Write the morning down as a failure. Public because the retry_on and
  # discard_on blocks are what call it, and they are handed the job rather
  # than executed inside it.
  #
  # The window is the one this attempt built, so a run that spent three
  # quarters of an hour retrying records the window as it stood at the last
  # attempt rather than the first — which is right: everything up to then has
  # now been considered and found unanswerable.
  def abandon(error, complaint = "no edition composed")
    Rails.logger.error("#{complaint}: #{error.message}")
    Edition::Gap.failed(window, error.message)
  end

  private

  # Memoised so the failure handlers close the same window #perform opened.
  # Reading the clock a second time inside a discard_on block would record a
  # gap whose window had drifted past the one composition actually tried.
  def window
    @_window ||= Edition::Window.new(Time.current)
  end

  # An empty window publishes nothing, per the PRD — no edition, no error, the
  # home page keeps showing the last one and its timestamp does the honesty
  # work. It is still written down: the window has been considered, and the
  # watermark has to move or tomorrow reconsiders it. Not drawn in the archive
  # either, which is the difference between this and a failure — a morning
  # nothing arrived on needs no explanation.
  #
  # Logged as well, because a morning with nothing in the window and a morning
  # where the scheduler never fired look identical in the log without this
  # line, and they want different fixing.
  def skipped
    Rails.logger.info("nothing has arrived since the last edition closed; nothing to compose")
    Edition::Gap.empty(window)
  end
end
