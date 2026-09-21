require "rails_helper"

RSpec.describe Edition::Recording::Presenter do
  def finished_recording_for(edition)
    recording = create(:edition_recording, edition: edition)
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
    create(:edition_recording, edition: edition)

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
    create(:edition_recording, edition: edition, failed_at: 1.minute.ago)

    expect(Edition::Recording::Presenter.new(edition.reload)).not_to be_preparing
  end

  it "invites the reader to play an edition nobody has asked about" do
    expect(Edition::Recording::Presenter.new(create(:edition)).invitation)
      .to eq("Play edition")
  end

  it "invites the reader to try again after a failure" do
    edition = create(:edition)
    create(:edition_recording, edition: edition, failed_at: 1.minute.ago)

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

  # The element the job writes into, which is also the page's live region. The
  # two have to name the same thing or the broadcast lands nowhere and the
  # preparing line never changes — and nothing else would notice.
  it "names the element the page keeps the recording in" do
    expect(Edition::Recording::Presenter.new(create(:edition)).frame)
      .to eq("edition_recording")
  end

  # A bare <audio> announces itself as "audio" and nothing else.
  it "gives the player an accessible name" do
    expect(Edition::Recording::Presenter.new(create(:edition)).label)
      .to eq("Listen to this edition")
  end

  it "says what is happening while the audio is being made" do
    expect(Edition::Recording::Presenter.new(create(:edition)).preparing_line)
      .to eq("Preparing the audio. It appears here when ready, or reload.")
  end

  # Every fact the broadcast needs is already here — the channel, the frame,
  # the partial and the local — so the job asks rather than assembling it.
  it "announces itself on the edition's own channel" do
    edition = create(:edition)

    expect { Edition::Recording::Presenter.new(edition).announce }
      .to have_broadcasted_to("edition_#{edition.id}_recording")
  end
end
