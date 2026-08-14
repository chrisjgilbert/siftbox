# The client Edition::Draft talks through, standing in for Anthropic::Client.
#
# A class with the real interface rather than a stubbed client, per
# .claude/rules/testing.md — and because the interface is the part most likely
# to be wrong. What comes back is a real Anthropic::Models::Message, built out
# of the same hash the API sends, so a spec cannot pass against a double whose
# stop_reason is a String where the SDK's is a Symbol.
#
# It records what it was asked for, because the request is most of what there
# is to test: nobody here can check whether the model wrote a good edition,
# but everybody can check that it was asked the way claude-opus-5 accepts.
class FakeAnthropic
  URL = URI("https://api.anthropic.com/v1/messages").freeze

  # Thinking is on by default on claude-opus-5 and the raw chain of thought is
  # never returned, so every real answer opens with a thinking block carrying
  # nothing. It is here so a reader that reaches for content[0] fails.
  THINKING = { type: "thinking", thinking: "", signature: "irrelevant" }.freeze

  attr_reader :messages

  # The SDK's errors carry the whole HTTP exchange, and .for picks the class
  # from the status the way a real response would.
  def self.api_error(status)
    Anthropic::Errors::APIStatusError.for(
      url: URL, status: status, headers: {}, body: nil, request: nil, response: nil
    )
  end

  def initialize(text: "{}", stop_reason: :end_turn, input_tokens: 0, output_tokens: 0, error: nil)
    @messages = Messages.new(
      message: message(text, stop_reason, input_tokens, output_tokens), error: error
    )
  end

  def request
    messages.requests.last
  end

  private

  def message(text, stop_reason, input_tokens, output_tokens)
    Anthropic::Models::Message.new(
      id: "msg_01", content: content(text, stop_reason), model: :"claude-opus-5",
      role: :assistant, stop_reason: stop_reason, stop_sequence: nil, type: :message,
      usage: { input_tokens: input_tokens, output_tokens: output_tokens }
    )
  end

  # A declined request answers 200 with nothing in it, which is the reason
  # stop_reason has to be read before the content is.
  def content(text, stop_reason)
    return [] if stop_reason == :refusal

    [ THINKING, { type: "text", text: text } ]
  end

  # client.messages
  class Messages
    attr_reader :requests

    def initialize(message:, error:)
      @message = message
      @error = error
      @requests = []
    end

    def stream(**request)
      @requests << request
      raise @error if @error

      Stream.new(@message)
    end
  end

  # What client.messages.stream answers: the assembled message is read off it
  # once the stream has run out, rather than returned directly.
  class Stream
    def initialize(message)
      @message = message
    end

    def accumulated_message
      @message
    end
  end
end
