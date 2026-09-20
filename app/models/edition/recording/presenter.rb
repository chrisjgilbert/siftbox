# Display logic for the one control the edition page carries: play the edition,
# or wait while it is being made, or offer to try again.
#
# Built for an edition rather than for a recording, because most editions have
# none — nothing is recorded until a reader asks — and a template cannot be left
# to ask whether the object it was handed exists. Every question below has an
# answer for an edition nobody has ever pressed play on.
#
# It lives on Edition::Presenter rather than beside it as a second helper, which
# is the opposite of the decision recorded there about the pen's badge. The
# reason is the same reason: the badge is about the reader's subscriptions and
# has no business reachable from the object the editor's words come out of,
# where this is the same edition in another medium.
class Edition::Recording::Presenter
  # One recording per page, so the id it is replaced at is a constant rather
  # than something derived. The job broadcasts to it when the audio is ready.
  FRAME = "edition_recording".freeze

  def initialize(edition)
    @edition = edition
  end

  def ready?
    recording.present? && recording.ready?
  end

  def preparing?
    recording.present? && recording.pending?
  end

  # "Play edition" the first time, and something that admits what happened after
  # a failure: offering the same words again would say nothing about why the
  # reader is being asked twice.
  def invitation
    return I18n.t("editions.recording.retry") if recording&.failed?

    I18n.t("editions.recording.play")
  end

  # Said while the audio is being made. It mentions reloading because the
  # broadcast that replaces this is the only part of the page that depends on a
  # live connection, and a reader whose connection dropped should not be left
  # watching a sentence that will never change.
  def preparing_line
    I18n.t("editions.recording.preparing")
  end

  # The accessible name of the audio element. A bare <audio> announces itself as
  # "audio" and nothing else.
  def label
    I18n.t("editions.recording.label")
  end

  def frame
    FRAME
  end

  # Both the address the button posts to and the one the player reads from: the
  # recording is a singular resource, so creating it and playing it are the same
  # path under different verbs.
  def path
    routes.edition_recording_path(edition)
  end

  # What the page subscribes to and what Edition::RecordingJob broadcasts on.
  # Named after the edition rather than the recording, because the page
  # subscribes before there is a recording to name.
  def channel
    "edition_#{edition.id}_recording"
  end

  private

  attr_reader :edition

  # Not memoised. The has_one association caches its own load, including the
  # absence of a row, which is the case a `||=` here would re-query on every
  # question the page asks.
  def recording
    edition.recording
  end

  # A presenter has no route helpers of its own, the way Newsletter::Presenter
  # has none either.
  def routes
    Rails.application.routes.url_helpers
  end
end
