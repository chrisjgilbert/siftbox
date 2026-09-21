require "rails_helper"

RSpec.describe "Edition recordings" do
  def edition_holding_audio(bytes: "the-exact-bytes", content_type: "audio/mpeg")
    edition = create(:edition)
    recording = create(:edition_recording, edition: edition)
    recording.audio.attach(
      io: StringIO.new(bytes), filename: "edition.mp3", content_type: content_type
    )
    recording.update!(completed_at: Time.current)

    edition
  end

  describe "asking for a recording" do
    it "starts one for a signed-in reader" do
      sign_in
      edition = create(:edition)

      post edition_recording_path(edition)

      expect(edition.reload.recording).to be_present
    end

    it "hands the work to a job" do
      sign_in
      edition = create(:edition)

      expect { post edition_recording_path(edition) }
        .to have_enqueued_job(Edition::RecordingJob)
    end

    # Back to the page the button is on, which then draws the preparing state
    # off the recording's own timestamps.
    it "returns the reader to the edition" do
      sign_in
      edition = create(:edition)

      post edition_recording_path(edition)

      expect(response).to redirect_to(edition_url(edition))
    end

    it "keeps a signed-out visitor from spending money" do
      edition = create(:edition)

      post edition_recording_path(edition)

      expect(response).to redirect_to(new_session_path)
    end

    it "enqueues nothing for a signed-out visitor" do
      edition = create(:edition)

      expect { post edition_recording_path(edition) }
        .not_to have_enqueued_job(Edition::RecordingJob)
    end

    # A second tap on a button nothing disables. The reader gets the recording
    # already being made rather than a collision on the unique index.
    it "answers a second ask with the recording already under way" do
      sign_in
      edition = create(:edition)

      post edition_recording_path(edition)
      post edition_recording_path(edition)

      expect(response).to redirect_to(edition_url(edition))
    end

    it "spends nothing on a second ask for the same edition" do
      sign_in
      edition = create(:edition)
      post edition_recording_path(edition)

      expect { post edition_recording_path(edition) }
        .not_to have_enqueued_job(Edition::RecordingJob)
    end

    # Edition.find typecasts, so "7abc" finds edition 7 and would otherwise be
    # echoed straight back into the Location header.
    it "sends the reader to the edition's canonical address" do
      sign_in
      edition = create(:edition)

      post "/editions/#{edition.id}abc/recording"

      expect(response).to redirect_to(edition_url(edition))
    end

    # The one create in this app that spends money per request. Every other one
    # is limited, and until this it was not.
    it "turns away a reader recording one edition after another" do
      sign_in
      editions = Array.new(6) { create(:edition) }

      editions.each { |edition| post edition_recording_path(edition) }

      expect(Edition::Recording.count).to eq(5)
    end

    it "says why it turned them away" do
      sign_in
      editions = Array.new(6) { create(:edition) }

      editions.each { |edition| post edition_recording_path(edition) }

      expect(flash[:alert])
        .to eq("That is a lot of editions to record at once. Try again in a minute.")
    end
  end

  describe "playing a recording" do
    it "serves the audio to a signed-in reader" do
      sign_in

      get edition_recording_path(edition_holding_audio)

      expect(response.body).to eq("the-exact-bytes")
    end

    it "serves it as audio" do
      sign_in

      get edition_recording_path(edition_holding_audio)

      expect(response.media_type).to eq("audio/mpeg")
    end

    # Without this a media element will not offer a scrubber, and Safari will
    # not play the source at all.
    it "says it will answer byte ranges" do
      sign_in

      get edition_recording_path(edition_holding_audio)

      expect(response.headers["Accept-Ranges"]).to eq("bytes")
    end

    it "keeps a signed-out visitor away from the audio" do
      get edition_recording_path(edition_holding_audio)

      expect(response).to redirect_to(new_session_path)
    end

    it "has nothing to play for an edition nobody has asked about" do
      sign_in

      get edition_recording_path(create(:edition))

      expect(response).to have_http_status(:not_found)
    end

    it "has nothing to play while the recording is still being made" do
      sign_in
      edition = create(:edition)
      create(:edition_recording, edition: edition)

      get edition_recording_path(edition)

      expect(response).to have_http_status(:not_found)
    end

    # The type on the blob is this app's own rather than a stranger's, so this
    # is a floor: it is here so the thing that writes the type and the thing
    # that serves it cannot drift apart without something saying so.
    it "refuses to serve a blob labelled as anything but audio" do
      sign_in

      get edition_recording_path(edition_holding_audio(content_type: "text/html"))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "seeking within a recording" do
    it "answers a range with just that range" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=2-5" }

      expect(response.body).to eq("2345")
    end

    it "answers a range with partial content" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=2-5" }

      expect(response).to have_http_status(:partial_content)
    end

    it "says which bytes it sent and how many there are" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=2-5" }

      expect(response.headers["Content-Range"]).to eq("bytes 2-5/10")
    end

    # What a media element sends first: everything from the start, so it can
    # read the duration out of the header and begin buffering.
    it "answers an open-ended range from the offset to the end" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=4-" }

      expect(response.body).to eq("456789")
    end

    it "refuses a range the file cannot satisfy" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=99-200" }

      expect(response).to have_http_status(:range_not_satisfiable)
    end

    # Without the real length on the refusal a player holding a stale duration
    # has nothing to correct itself with, and gives up rather than re-asking.
    it "says how long the file really is when it refuses a range" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=99-200" }

      expect(response.headers["Content-Range"]).to eq("bytes */10")
    end

    # Answering 416 to a range that could be satisfied leaves a player with no
    # audio at all. Ignoring the header and sending the whole file is what the
    # spec allows and what every client accepts.
    it "sends the whole file for a multipart range no player asks for" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "bytes=0-1,4-5" }

      expect(response.body).to eq("0123456789")
    end

    it "sends the whole file for a header that is not a byte range at all" do
      sign_in

      get edition_recording_path(edition_holding_audio(bytes: "0123456789")),
        headers: { "Range" => "items=0-1" }

      expect(response.body).to eq("0123456789")
    end
  end
end
