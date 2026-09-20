require "rails_helper"

RSpec.describe Edition::RecordingJob do
  # Every attempt the job is entitled to, run the way a worker would run them:
  # the first here, then each enqueued retry taken off the queue in turn. The
  # same seam Edition::CompositionJob's spec uses, and for the same reason.
  def run_every_attempt(recording)
    Edition::RecordingJob.perform_now(recording)
    ActiveJob::Base.execute(enqueued_jobs.shift) while enqueued_jobs.any?
  end

  def an_edition_of_one_story
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "Figma filed", body: "The S-1 landed.")

    edition
  end

  it "keeps the audio the voice made" do
    with_a_voice do
      speaking(bytes: "the-exact-bytes")
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      Edition::RecordingJob.perform_now(recording)

      expect(recording.reload.audio.download).to eq("the-exact-bytes")
    end
  end

  it "records which voice read it" do
    with_a_voice do
      speaking
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      Edition::RecordingJob.perform_now(recording)

      expect(recording.reload.voice)
        .to eq("elevenlabs/eleven_flash_v2_5/#{VoiceServing::VOICE_ID}")
    end
  end

  # What gets spoken is Edition::Script's answer and nothing assembled here, so
  # the words on the wire are the words the page shows.
  it "sends the edition's own script to be read" do
    with_a_voice do
      edition = an_edition_of_one_story
      request = stub_request(:post, voice_url)
        .with(body: hash_including(text: Edition::Script.new(edition).text))
        .to_return(body: VoiceServing::AUDIO, headers: { "Content-Type" => "audio/mpeg" })

      Edition::RecordingJob.perform_now(create(:edition_recording, edition: edition))

      expect(request).to have_been_requested
    end
  end

  it "tries again when the voice is briefly unavailable" do
    with_a_voice do
      refusing_to_speak(status: 429)
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      expect { Edition::RecordingJob.perform_now(recording) }
        .to have_enqueued_job(Edition::RecordingJob)
    end
  end

  # The reader is watching a button that says the audio is being prepared, so
  # the failure has to reach the page rather than only the log.
  it "marks the recording failed once the attempts are spent" do
    with_a_voice do
      refusing_to_speak(status: 429)
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      run_every_attempt(recording)

      expect(recording.reload).to be_failed
    end
  end

  it "marks the recording failed when the voice refuses the request" do
    with_a_voice do
      refusing_to_speak(status: 401)
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      Edition::RecordingJob.perform_now(recording)

      expect(recording.reload).to be_failed
    end
  end

  # A wrong key is a wrong key on the second attempt too, and each attempt is a
  # request that costs.
  it "does not try again when the voice refuses the request" do
    with_a_voice do
      refusing_to_speak(status: 401)
      recording = create(:edition_recording, edition: an_edition_of_one_story)

      expect { Edition::RecordingJob.perform_now(recording) }
        .not_to have_enqueued_job(Edition::RecordingJob)
    end
  end

  # An edition destroyed while its recording was being made. There is nothing
  # left to record and nothing waiting will bring it back.
  it "gives up on a recording that has gone" do
    with_a_voice do
      speaking
      recording = create(:edition_recording, edition: an_edition_of_one_story)
      job = Edition::RecordingJob.new(recording)
      recording.destroy!

      expect { ActiveJob::Base.execute(job.serialize) }.not_to raise_error
    end
  end
end
