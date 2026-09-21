require "rails_helper"

RSpec.describe Edition::Voice do
  # Stubbed on the thing being asserted rather than asserted after the fact:
  # WebMock refuses a request no stub matches, so a narrowed stub that was
  # requested is the assertion.
  def speaking_only_when(**expected)
    stub_request(:post, voice_url).with(**expected)
      .to_return(body: VoiceServing::AUDIO, headers: { "Content-Type" => "audio/mpeg" })
  end

  it "sends the words it was given as the text to speak" do
    with_a_voice do
      request = speaking_only_when(body: hash_including(text: "Edition 14, Tuesday 11 August."))

      Edition::Voice.new("Edition 14, Tuesday 11 August.").speak

      expect(request).to have_been_requested
    end
  end

  # Flash rather than the multilingual default: an edition is read once a
  # morning in one language, and the cheaper model is the one to find out with.
  it "asks for the model the app has chosen rather than the vendor's default" do
    with_a_voice do
      request = speaking_only_when(body: hash_including(model_id: "eleven_flash_v2_5"))

      Edition::Voice.new("Anything.").speak

      expect(request).to have_been_requested
    end
  end

  # 64 kbps mono-ish speech, which halves the file against the vendor's 128
  # default and is indistinguishable on a phone. The query parameter is where
  # this vendor takes it, not the body.
  it "asks for the audio format the app serves" do
    with_a_voice do
      request = speaking_only_when(query: { output_format: "mp3_44100_64" })

      Edition::Voice.new("Anything.").speak

      expect(request).to have_been_requested
    end
  end

  it "authenticates with the key in the environment" do
    with_a_voice do
      request = speaking_only_when(headers: { "xi-api-key" => VoiceServing::KEY })

      Edition::Voice.new("Anything.").speak

      expect(request).to have_been_requested
    end
  end

  it "answers the audio the vendor sent, byte for byte" do
    with_a_voice do
      speaking(bytes: "the-exact-bytes")

      expect(Edition::Voice.new("Anything.").speak).to eq("the-exact-bytes")
    end
  end

  # Recorded on the row beside the audio, the way editions.editor_model records
  # which model wrote the words, so a recording that sounds wrong months later
  # can be told from one made by a voice since changed.
  it "names itself by vendor, model and voice" do
    with_a_voice do
      expect(Edition::Voice.new("Anything.").name)
        .to eq("elevenlabs/eleven_flash_v2_5/#{VoiceServing::VOICE_ID}")
    end
  end

  it "reports a rate limit as something waiting might fix" do
    with_a_voice do
      refusing_to_speak(status: 429)

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Unavailable)
    end
  end

  it "reports a server error as something waiting might fix" do
    with_a_voice do
      refusing_to_speak(status: 503)

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Unavailable)
    end
  end

  it "reports an unreachable vendor as something waiting might fix" do
    with_a_voice do
      unreachable

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Unavailable)
    end
  end

  # A wrong key, a voice that does not exist, a model that has been retired:
  # all of them are this app's to fix and none of them is fixed by asking again.
  it "reports a refused request as ours to fix" do
    with_a_voice do
      refusing_to_speak(status: 401)

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Rejected)
    end
  end

  # The vendor answering 200 with JSON is the vendor explaining itself, and what
  # it has to explain is the request. Stored unchecked, it would reach the
  # reader as a player that plays nothing.
  it "reports an answer that is not audio as ours to fix" do
    with_a_voice do
      refusing_to_speak(status: 200, body: { detail: "voice not found" }.to_json)

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Rejected, /audio/)
    end
  end

  # Audio of nothing is a different failure from audio of the wrong thing:
  # there is no explanation to read, and one more request is cheap.
  it "reports audio with nothing in it as something waiting might fix" do
    with_a_voice do
      speaking(bytes: "")

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Unavailable)
    end
  end

  # A voice id is pasted in by hand, so it arrives with a trailing space often
  # enough to matter. Unescaped it makes URI() raise, which is none of this
  # class's errors; escaped it is an ordinary 404 that says what is wrong.
  it "escapes a voice id rather than letting it rewrite the address" do
    with_a_voice do
      ENV["ELEVENLABS_VOICE_ID"] = "a voice"
      stub_request(:post, %r{/v1/text-to-speech/a%20voice})
        .to_return(status: 404, headers: { "Content-Type" => "application/json" })

      expect { Edition::Voice.new("Anything.").speak }
        .to raise_error(Edition::Voice::Rejected)
    end
  end

  # Read where it is used rather than at class load, so a deploy without it
  # fails on the name of the thing missing rather than at boot.
  #
  # The key is deleted rather than assumed absent: developers are told to keep
  # it in the environment for bin/rails "edition:record", so without this the
  # example passes on CI and fails for exactly the people working on this.
  it "fails on the name of the missing variable when the key is not set" do
    key = ENV.delete("ELEVENLABS_API_KEY")
    voice = ENV["ELEVENLABS_VOICE_ID"]
    ENV["ELEVENLABS_VOICE_ID"] = VoiceServing::VOICE_ID

    expect { Edition::Voice.new("Anything.").speak }
      .to raise_error(KeyError, /ELEVENLABS_API_KEY/)
  ensure
    ENV["ELEVENLABS_API_KEY"] = key
    ENV["ELEVENLABS_VOICE_ID"] = voice
  end
end
