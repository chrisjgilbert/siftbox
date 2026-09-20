# The voice served over the wire, for the specs that go through the real
# request rather than around it.
#
# WebMock rather than a fake client, unlike FakeAnthropic: there is no vendor
# gem here and Edition::Voice builds the request itself out of Net::HTTP, so
# the request is the thing worth asserting on and the wire is where it can be
# seen. It is also the only seam a job spec has — a job takes serialisable
# arguments and cannot be handed a client.
module VoiceServing
  KEY = "not-a-key".freeze
  VOICE_ID = "a-voice-id".freeze

  # Not real MP3 frames. Nothing in this app parses the audio — it is stored
  # and served as bytes — so what matters about this string is only that it
  # arrives intact.
  AUDIO = "ID3\x04and then some frames".freeze

  def voice_url
    "https://api.elevenlabs.io/v1/text-to-speech/#{VOICE_ID}" \
      "?output_format=#{Edition::Voice::FORMAT}"
  end

  def speaking(bytes: AUDIO)
    stub_request(:post, voice_url)
      .to_return(body: bytes, headers: { "Content-Type" => "audio/mpeg" })
  end

  def refusing_to_speak(status:, body: "", type: "application/json")
    stub_request(:post, voice_url)
      .to_return(status: status, body: body, headers: { "Content-Type" => type })
  end

  def unreachable
    stub_request(:post, voice_url).to_raise(Errno::ECONNREFUSED)
  end

  # Both variables set for the block and put back after, because Edition::Voice
  # fetches rather than reads them: absent, an example fails on a KeyError
  # about the variable rather than on what it was looking at.
  def with_a_voice
    key = ENV["ELEVENLABS_API_KEY"]
    voice = ENV["ELEVENLABS_VOICE_ID"]
    ENV["ELEVENLABS_API_KEY"] = KEY
    ENV["ELEVENLABS_VOICE_ID"] = VOICE_ID

    yield
  ensure
    ENV["ELEVENLABS_API_KEY"] = key
    ENV["ELEVENLABS_VOICE_ID"] = voice
  end
end

RSpec.configure do |config|
  config.include VoiceServing
end
