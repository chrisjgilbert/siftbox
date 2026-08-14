# The edition as the model wrote it, before anything has checked it.
#
# This owns one thing: send the prompt, and hand back what came out of it
# parsed. It knows nothing about Edition rows, citations or whether the
# stories it returns cite every newsletter in the window — that check belongs
# to whoever is composing an edition, and putting it here would mean the
# object that talks to the API is also the object that decides what a valid
# edition is.
class Edition::Draft
  # A Symbol, which is how the Ruby SDK takes a model. The alias carries no
  # date suffix; appending one 404s.
  MODEL = :"claude-opus-5"

  # Inside output_config, next to the output format rather than beside it at
  # the top level. High is the default and stated anyway: it is the setting
  # the day's clustering is judged at, and a default that moves under us would
  # move the editions with it.
  EFFORT = "high".freeze

  # Thinking is on by default on this model and counts against the same
  # ceiling as the answer, so this is not "how long an edition is" — it is an
  # edition plus however far the model got into working out what the stories
  # were. Fifteen stories of prose is a few thousand tokens; the rest is the
  # thinking. Sized too tightly it does not cut the reasoning short, it cuts
  # the JSON the reasoning was leading up to, and a half-written edition reads
  # as a parser bug rather than as a budget.
  MAX_TOKENS = 32_000

  # What the PRD's editions table wants stored, alongside the stories
  # themselves: enough to read a bad edition back months later and to write it
  # again after a prompt change without asking every newsletter for its body a
  # second time.
  Copy = Data.define(
    :stories, :model, :prompt_version, :input_tokens, :output_tokens, :raw_response
  )

  # One family, so a caller with nothing to do about any of them can say so in
  # one rescue, and one with something to do about a rate limit can still tell
  # it from a refusal.
  Error = Class.new(StandardError)

  # A safety classifier declined. It arrives as a perfectly ordinary 200 with
  # an empty content array, which is why stop_reason is read before content
  # is: indexing content[0] here raises about a nil and says nothing about
  # what happened.
  Refused = Class.new(Error)

  # The answer ran into MAX_TOKENS. Structured output guarantees the JSON is
  # well formed right up until it stops, so this would otherwise surface as a
  # parse error two methods away from the cause.
  Truncated = Class.new(Error)

  # Nothing usable came back and nothing here can fix it: the next run gets an
  # edition, this one does not.
  Unavailable = Class.new(Error)

  # The API understood the request and refused it — a bad schema, a missing
  # key, a model that is not there. Waiting does not help; this is ours.
  Rejected = Class.new(Error)

  # The client is injected so specs can pass a fake rather than stub HTTP.
  # Left nil rather than defaulted to a real client, so building one is
  # something #write does and not something `new` does — see #client.
  def initialize(prompt, client: nil)
    @prompt = prompt
    @client = client
  end

  def write
    answered(streamed)
  end

  private

  attr_reader :prompt

  # Streamed rather than asked for whole: at MAX_TOKENS with thinking on, an
  # answer takes minutes to arrive, and a request that sends nothing for that
  # long is a request something between here and Anthropic eventually gives up
  # on. The assembled message is read back off the stream at the end, so
  # nothing downstream has to know it arrived in pieces.
  #
  # Most specific first. The SDK already retries 429s and 5xx with backoff, so
  # reaching a rescue means it has run out of attempts and a loop around this
  # would only multiply that out. Each raise keeps the SDK's error as its
  # cause, so the status code is still in the backtrace.
  def streamed
    client.messages.stream(**request).accumulated_message
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError => error
    raise Unavailable, "the model could not answer: #{error.message}"
  rescue Anthropic::Errors::APIConnectionError => error
    raise Unavailable, "the model could not be reached: #{error.message}"
  rescue Anthropic::Errors::APIStatusError => error
    raise Rejected, "the request was refused: #{error.message}"
  end

  # Both stop reasons come back as Symbols, not Strings.
  def answered(response)
    raise Refused, "the model declined to write the edition" if response.stop_reason == :refusal
    raise Truncated, "the edition ran past #{MAX_TOKENS} tokens" if response.stop_reason == :max_tokens

    copy(response)
  end

  def copy(response)
    Copy.new(
      stories: stories(response), model: response.model.to_s,
      prompt_version: prompt.version, input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens, raw_response: response.to_h.to_json
    )
  end

  # fetch rather than [], because a response with no stories at all is the
  # schema having stopped being enforced, and that should be loud.
  def stories(response)
    JSON.parse(text(response), symbolize_names: true).fetch(:stories)
  end

  # Not content[0]: the first block is the thinking block, empty because the
  # raw chain of thought is never returned but there all the same.
  #
  # An answer with no text block at all is not a shape the API documents — a
  # decline is :refusal and a cut-off answer is :max_tokens, and both are
  # already out of the way. Reading through the nil would blame JSON for it.
  def text(response)
    block = response.content.detect { |content| content.type == :text }
    return block.text if block

    raise Error, "the model answered nothing, stopping on #{response.stop_reason}"
  end

  # Sampling parameters are deliberately absent: temperature, top_p and top_k
  # are all 400s on this model rather than settings it ignores. So is a
  # thinking budget — thinking is adaptive here, and the prompt is what steers
  # the answer.
  def request
    {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system_: prompt.instructions,
      messages: [ { role: "user", content: prompt.sources } ],
      output_config: {
        effort: EFFORT,
        format: { type: "json_schema", schema: prompt.schema }
      }
    }
  end

  # The key is read here rather than at class load. A constant would be
  # evaluated when Rails eager-loads this file, so a deploy without the
  # variable set would fail at boot — every page, every job, every spec —
  # rather than failing where it is used with the name of the thing missing.
  def client
    @client ||= Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end
end
