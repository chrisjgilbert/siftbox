require "net/http"

# The voice that reads an edition: hand it words, get back audio.
#
# It owns one thing — one request to the vendor — and knows nothing about
# editions, recordings or where the audio is going to be stored, for the same
# reason Edition::Draft knows nothing about Edition rows. What it does know is
# which failures are worth a second attempt and which are this app's to fix,
# because the status code is the only place that can be told apart.
#
# The Claude API has no text-to-speech, so this is a second vendor and a second
# key rather than another call through the one already in the Gemfile. There is
# no gem: the request is a POST with a JSON body and audio bytes coming back,
# which Net::HTTP does without a dependency to keep current.
#
# Whether one request can hold a whole edition is the reason this vendor and
# this model: eleven_flash_v2_5 takes 40,000 characters, and an edition is a
# few thousand. Google's synchronous endpoint caps at 5,000 bytes and cannot be
# raised, which would mean splitting the edition and stitching the pieces back
# together — an ffmpeg dependency in the image for nothing the reader hears.
class Edition::Voice
  ENDPOINT = "https://api.elevenlabs.io/v1/text-to-speech".freeze

  VENDOR = "elevenlabs".freeze

  # Flash rather than the multilingual default. An edition is read once a
  # morning in one language, and this is a third of the price. Changing it is
  # one line, and the voice it was made with is recorded on every recording, so
  # a change can be heard against what came before it.
  MODEL = "eleven_flash_v2_5".freeze

  # codec_samplerate_bitrate, as this vendor spells it. 64 kbps halves the file
  # against their 128 default and is indistinguishable for speech on a phone;
  # 192 is the first format that needs a paid tier, and this is not it.
  FORMAT = "mp3_44100_64".freeze

  # What the vendor sends and what this app stores. Checked on the way in
  # rather than trusted, because a 200 carrying JSON is this vendor's way of
  # explaining a bad request, and stored unchecked it reaches the reader as a
  # player that plays nothing.
  CONTENT_TYPE = "audio/mpeg".freeze

  # What a file of it is called, beside the type rather than spelled out
  # wherever a filename is built. FORMAT is the one decision and these two
  # follow from it: an Opus variant would otherwise leave blobs typed audio/ogg
  # and still named .mp3, which is the half of the drift the constant above was
  # added to close.
  EXTENSION = "mp3".freeze

  OPEN_TIMEOUT = 5

  # Generous, and deliberately: a job can wait, and an edition cut off halfway
  # through synthesis costs the whole request rather than part of it.
  READ_TIMEOUT = 120

  # The ordinary ways a request to somebody else's server dies, which this app
  # has already had to enumerate once for the fetches that go the other way.
  # Listed again here it would be two lists that have to be kept in step with
  # nothing linking them, and Download's is already the canonical one — a blog
  # spec reasons about membership in it by name. Its two extras cost nothing:
  # there is no gzip on this response, and URI::Error is designed out by the
  # escaping in #uri.
  FAILURES = Download::FAILURES

  # The family the two below belong to. Nothing rescues it and nothing should:
  # Edition::RecordingJob names the two children one by one on purpose, so that
  # a third raised here later falls to its catch-all and gets stamped on the
  # row rather than being let through by a rule written before it existed. It
  # is here to say the two are one kind of thing, and for a console.
  Error = Class.new(StandardError)

  # Waiting might fix it: a rate limit, a server error, an unreachable host, or
  # a 200 with no audio in it.
  Unavailable = Class.new(Error)

  # Waiting will not fix it: a wrong key, a voice that does not exist, a model
  # that has been retired, a body the API refuses. This is ours, and it is
  # fixed by a deploy or a variable rather than by asking again.
  Rejected = Class.new(Error)

  def initialize(words)
    @words = words
  end

  # What made this recording, for the row beside the audio. Vendor, model and
  # voice, because all three can change under a reader who only knows that
  # last month's editions sounded different.
  def name
    "#{VENDOR}/#{MODEL}/#{voice_id}"
  end

  def speak
    audio_from(answered)
  end

  private

  attr_reader :words

  def answered
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
  rescue *FAILURES => error
    raise Unavailable, "the voice could not be reached: #{error.message}"
  end

  # Most specific first, and the split is the whole point of reading the status
  # here: a 429 today is audio tomorrow, and a 401 today is a 401 forever.
  # #empty? rather than #blank?, which looks like the same question and is not
  # at this size. Active Support's is `empty? || BLANK_RE.match?(self)`, and
  # matching an ASCII regex against a megabytes-long ASCII-8BIT body full of
  # high bytes raises Encoding::CompatibilityError, gets rescued inside Active
  # Support, and scans the whole body a second time — twice over every
  # successful edition, to answer a question #empty? answers in constant time.
  def audio_from(response)
    raise Unavailable, "the voice could not answer: #{response.code}" if waiting_helps?(response)
    raise Rejected, "the voice refused the request: #{response.code}" unless response.is_a?(Net::HTTPOK)
    raise Rejected, "the voice answered #{content_type(response)} rather than audio" unless audio?(response)

    audio = response.body.to_s
    raise Unavailable, "the voice answered no audio at all" if audio.empty?

    audio
  end

  def waiting_helps?(response)
    response.is_a?(Net::HTTPTooManyRequests) || response.is_a?(Net::HTTPServerError)
  end

  def audio?(response)
    content_type(response) == CONTENT_TYPE
  end

  # Net::HTTP parses this header itself — #content_type splits the parameters
  # off and strips what is left, and answers nil when the header is absent — so
  # the type and the charset never have to be told apart here. to_s covers the
  # absent case and downcase the sender who shouted it.
  def content_type(response)
    response.content_type.to_s.downcase
  end

  def request
    Net::HTTP::Post.new(uri).tap do |post|
      post["xi-api-key"] = ENV.fetch("ELEVENLABS_API_KEY")
      post["Content-Type"] = "application/json"
      post["Accept"] = CONTENT_TYPE
      post.body = { text: words, model_id: MODEL }.to_json
    end
  end

  # The voice id is escaped rather than interpolated raw. It comes from the
  # environment and gets pasted in by hand, so it arrives with a trailing space
  # often enough to matter — and a space makes URI() raise
  # URI::InvalidURIError, which is not one of FAILURES and is neither
  # Unavailable nor Rejected, so it would leave the request breaking off
  # somewhere nothing here describes. A value carrying a slash or a question
  # mark is worse than that: it does not raise, it quietly rewrites the path or
  # the query and posts to an endpoint nobody meant. Escaped, both become an
  # ordinary 404 from the vendor, which is a Rejected that says so.
  def uri
    @_uri ||= URI("#{ENDPOINT}/#{ERB::Util.url_encode(voice_id)}?output_format=#{FORMAT}")
  end

  # Both variables are read here rather than at class load, for the reason
  # Edition::Draft gives about its own key: a constant would be evaluated when
  # Rails eager-loads this file, so a deploy with the variable missing would
  # fail at boot — every page, every job — rather than failing where it is used
  # with the name of the thing missing.
  #
  # Which voice reads the edition is a matter of taste, so it lives in the
  # environment: changing it is a deploy variable rather than a deploy.
  def voice_id
    ENV.fetch("ELEVENLABS_VOICE_ID")
  end
end
