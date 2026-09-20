require "rails_helper"

RSpec.describe Edition::Recording do
  it { is_expected.to belong_to(:edition) }

  it "allows one recording per edition" do
    edition = create(:edition)
    create(:edition_recording, edition: edition)

    expect(build(:edition_recording, edition: edition)).not_to be_valid
  end

  describe ".start" do
    it "records that an edition has been asked for" do
      edition = create(:edition)

      recording = Edition::Recording.start(edition)

      expect(recording.requested_at).to be_present
    end

    it "hands the work to a job rather than doing it here" do
      edition = create(:edition)

      expect { Edition::Recording.start(edition) }
        .to have_enqueued_job(Edition::RecordingJob)
    end

    # A second tap on a button that is still preparing, or a reader coming back
    # to an edition whose recording failed yesterday. Either way there is one
    # recording per edition and the unique index says so, so asking again reuses
    # the row rather than colliding with it.
    it "asks again on the recording an edition already has" do
      edition = create(:edition)
      first = create(:edition_recording, edition: edition)

      expect(Edition::Recording.start(edition)).to eq(first)
    end

    it "clears an earlier failure when asked again" do
      edition = create(:edition)
      create(:edition_recording, edition: edition, failed_at: 1.day.ago)

      expect(Edition::Recording.start(edition)).not_to be_failed
    end

    it "moves the moment it was asked for when asked again" do
      edition = create(:edition)
      create(:edition_recording, edition: edition, requested_at: 1.day.ago)

      expect(Edition::Recording.start(edition).requested_at).to be_within(1.minute).of(Time.current)
    end
  end

  describe "#store" do
    it "keeps the audio it was given" do
      recording = create(:edition_recording)

      recording.store("the-exact-bytes", voice: "elevenlabs/a-model/a-voice")

      expect(recording.audio.download).to eq("the-exact-bytes")
    end

    it "records which voice said it" do
      recording = create(:edition_recording)

      recording.store("audio", voice: "elevenlabs/a-model/a-voice")

      expect(recording.voice).to eq("elevenlabs/a-model/a-voice")
    end

    # The filename is what a reader gets if they save the file, so it names the
    # edition rather than the row.
    it "names the file after the edition it reads" do
      recording = create(:edition_recording, edition: create(:edition, number: 14))

      recording.store("audio", voice: "a-voice")

      expect(recording.audio.filename.to_s).to eq("edition-14.mp3")
    end

    it "is ready once it holds audio" do
      recording = create(:edition_recording)

      recording.store("audio", voice: "a-voice")

      expect(recording).to be_ready
    end

    # A retry that works. Without this the recording plays and still reads as
    # failed, and the page would offer to make it again.
    it "clears an earlier failure" do
      recording = create(:edition_recording, failed_at: 1.day.ago)

      recording.store("audio", voice: "a-voice")

      expect(recording).not_to be_failed
    end
  end

  describe "#abandon" do
    it "marks the recording failed" do
      recording = create(:edition_recording)

      recording.abandon

      expect(recording).to be_failed
    end

    it "is no longer pending once abandoned" do
      recording = create(:edition_recording)

      recording.abandon

      expect(recording).not_to be_pending
    end
  end

  describe "#pending?" do
    it "is pending while it has been asked for and nothing has come back" do
      expect(create(:edition_recording)).to be_pending
    end

    it "is not pending once it holds audio" do
      recording = create(:edition_recording)
      recording.store("audio", voice: "a-voice")

      expect(recording).not_to be_pending
    end
  end

  describe "#ready?" do
    # completed_at alone is not enough. A purged blob leaves the stamp behind,
    # and a page that trusted the stamp would draw a player with no source.
    it "is not ready with a completion stamp but no audio" do
      recording = create(:edition_recording, completed_at: 1.hour.ago)

      expect(recording).not_to be_ready
    end

    it "is not ready before anything has come back" do
      expect(create(:edition_recording)).not_to be_ready
    end
  end
end
