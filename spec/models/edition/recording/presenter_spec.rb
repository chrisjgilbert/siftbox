require "rails_helper"

RSpec.describe Edition::Recording::Presenter do
  def recording_for(edition, **attributes)
    create(:edition_recording, edition: edition, **attributes)
  end

  def finished_recording_for(edition)
    recording = recording_for(edition)
    recording.store("audio", voice: "a-voice")

    recording
  end

  it "has something to play once the recording holds audio" do
    edition = create(:edition)
    finished_recording_for(edition)

    expect(Edition::Recording::Presenter.new(edition.reload)).to be_ready
  end

  it "has nothing to play for an edition nobody has asked about" do
    expect(Edition::Recording::Presenter.new(create(:edition))).not_to be_ready
  end

  it "is preparing while the recording has been asked for and nothing has come back" do
    edition = create(:edition)
    recording_for(edition)

    expect(Edition::Recording::Presenter.new(edition.reload)).to be_preparing
  end

  it "is not preparing for an edition nobody has asked about" do
    expect(Edition::Recording::Presenter.new(create(:edition))).not_to be_preparing
  end

  it "is not preparing once there is something to play" do
    edition = create(:edition)
    finished_recording_for(edition)

    expect(Edition::Recording::Presenter.new(edition.reload)).not_to be_preparing
  end

  # A failure is neither playing nor preparing, so the page falls back to the
  # button — under a different word, because offering "Play edition" again after
  # it did not work says nothing about what happened.
  it "is not preparing once the recording has failed" do
    edition = create(:edition)
    recording_for(edition, failed_at: 1.minute.ago)

    expect(Edition::Recording::Presenter.new(edition.reload)).not_to be_preparing
  end

  it "invites the reader to play an edition nobody has asked about" do
    expect(Edition::Recording::Presenter.new(create(:edition)).invitation)
      .to eq("Play edition")
  end

  it "invites the reader to try again after a failure" do
    edition = create(:edition)
    recording_for(edition, failed_at: 1.minute.ago)

    expect(Edition::Recording::Presenter.new(edition.reload).invitation)
      .to eq("Try preparing the audio again")
  end

  it "answers at the edition's own recording address" do
    edition = create(:edition)

    expect(Edition::Recording::Presenter.new(edition).path)
      .to eq("/editions/#{edition.id}/recording")
  end

  # What the page subscribes to and what the job broadcasts on. Derived from the
  # edition rather than the recording, because the page subscribes before there
  # is a recording to name.
  it "names a channel of the edition's own" do
    edition = create(:edition)

    expect(Edition::Recording::Presenter.new(edition).channel)
      .to eq("edition_#{edition.id}_recording")
  end
end
