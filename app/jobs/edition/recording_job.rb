# Reading one edition aloud, because a reader asked for it.
#
# A job rather than the request that asked, for the ordinary reason: synthesis
# takes seconds, and a controller action that waits holds one of three Puma
# threads while it does. What the reader gets instead is a page that says the
# audio is being prepared, and the recording's own timestamps are what that page
# reads.
#
# Not enqueued at 07:00 and deliberately not: Edition::CompositionJob is
# untouched by this feature, so a vendor outage cannot cost the day its edition,
# and an edition nobody listens to costs nothing to have recorded.
class Edition::RecordingJob < ApplicationJob
  # Three attempts thirty seconds apart, where composition allows four at
  # fifteen minutes. The difference is who is waiting: nobody is watching the
  # morning's composition, and a reader who has just pressed play is watching
  # this. A minute of trying is worth it; three quarters of an hour would only
  # tell them nothing while they gave up and read the edition instead.
  ATTEMPTS = 3
  WAIT = 30.seconds

  # The failure worth waiting for, and once the waiting is spent the recording
  # carries the failure rather than the queue: the reader is looking at the page,
  # and the page reads the row.
  retry_on Edition::Voice::Unavailable, wait: WAIT, attempts: ATTEMPTS do |job, error|
    abandon(job.arguments.first, error)
  end

  # A wrong key, a voice that no longer exists, a model that has been retired.
  # Every attempt costs a request and none of them would answer differently.
  discard_on(Edition::Voice::Rejected) { |job, error| abandon(job.arguments.first, error) }

  # The edition was destroyed while its recording was being made, which takes
  # the recording with it. There is nothing left to record and nothing to tell
  # the reader, because the page that would have said so has gone too.
  discard_on(ActiveJob::DeserializationError) do |_job, error|
    Rails.logger.info("nothing left to record: #{error.message}")
  end

  # Logged as well as stamped, and then announced. The stamp is what the page
  # draws; the log is the only place that says which edition and why, and a
  # recording that failed looks the same on the page whatever the cause.
  def self.abandon(recording, error)
    recording.abandon

    Rails.logger.error(
      "no recording for edition #{recording.edition_id}: #{error.message}"
    )
    announce(recording)
  end

  # The reader is looking at a line that says the audio is being prepared, and
  # this is what replaces it — with the player, or with the offer to try again.
  #
  # Broadcast from the job rather than from a callback on Edition::Recording, so
  # the model stays clear of partials and locals, and because a recording that
  # changes for any other reason has nothing to announce.
  #
  # In development this reaches nothing: the cable adapter there is :async, which
  # only carries within one process, and bin/dev runs the worker beside the
  # server rather than inside it. Reloading the page shows the same thing, which
  # is what the preparing line tells the reader to do.
  # An update rather than a replace: the element this writes into is the live
  # region the page announces the change through, and replacing the region
  # itself is what a screen reader is least reliable about noticing. Writing
  # inside it leaves the region in place across every state.
  def self.announce(recording)
    presenter = Edition::Recording::Presenter.new(recording.edition)

    Turbo::StreamsChannel.broadcast_update_to(
      presenter.channel, target: presenter.frame,
      partial: "editions/recording", locals: { recording: presenter }
    )
  end

  # The voice is asked its name as well as for the audio, so what is stored
  # beside the bytes is what actually said them rather than what this file
  # thought it would be.
  #
  # The two rescues are in this order for a reason. The class-level handlers
  # above already own the two Edition::Voice errors — one waits and tries
  # again, one gives up — so they are let through untouched, and catching them
  # here would end an attempt the first time a rate limit paused it.
  #
  # Everything else is caught because nothing else would catch it, and a row
  # nothing stamps reads as "still being made" for ever. The likeliest is a
  # KeyError from an unset ELEVENLABS_API_KEY or ELEVENLABS_VOICE_ID on a
  # deployment that has just added this feature; a disk that will not take the
  # blob and a bug in here land the same way. Stamped and re-raised, so the
  # reader gets the button back and the queue still records a failed job.
  def perform(recording)
    voice = Edition::Voice.new(Edition::Script.new(recording.edition).text)

    recording.store(voice.speak, voice: voice.name)
    self.class.announce(recording)
  rescue Edition::Voice::Unavailable, Edition::Voice::Rejected
    raise
  rescue StandardError => error
    self.class.abandon(recording, error)
    raise
  end
end
