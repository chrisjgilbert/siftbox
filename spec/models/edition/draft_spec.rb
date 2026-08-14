require "rails_helper"

RSpec.describe Edition::Draft do
  # Which newsletters these are does not matter to anything here. What the
  # prompt makes of them is Edition::Prompt's spec; what matters below is that
  # whatever it made of them is what got sent.
  def newsletters
    [ build_stubbed(:newsletter, body_html: "<p>Figma filed on Tuesday.</p>") ]
  end

  # One story, in the shape the schema asks for. Nothing here checks whether
  # it is a good story — a fake cannot answer that, and a spec that asserted
  # it would only be reading back what this method wrote.
  def one_story
    {
      stories: [
        {
          headline: "Figma filed", body: "Money Stuff read the S-1.",
          section: "lead", newsletter_ids: [ 1 ]
        }
      ]
    }.to_json
  end

  it "asks claude-opus-5 for the edition" do
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(client.request[:model]).to eq(:"claude-opus-5")
  end

  it "sends the editor its instructions as the system prompt" do
    prompt = Edition::Prompt.new(newsletters)
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(prompt, client: client).write

    expect(client.request[:system_]).to eq(prompt.instructions)
  end

  it "sends the newsletters as the only thing the reader said" do
    prompt = Edition::Prompt.new(newsletters)
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(prompt, client: client).write

    expect(client.request[:messages]).to eq([ { role: "user", content: prompt.sources } ])
  end

  it "asks for the edition in the shape the prompt describes" do
    prompt = Edition::Prompt.new(newsletters)
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(prompt, client: client).write

    expect(client.request[:output_config][:format])
      .to eq(type: "json_schema", schema: prompt.schema)
  end

  # Inside output_config, not beside it. A top-level effort is not a parameter
  # the API has.
  it "asks for the effort the clustering is worth" do
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(client.request[:output_config][:effort]).to eq("high")
  end

  # Every one of these is a 400 on claude-opus-5 rather than a setting it
  # ignores, and a 400 is not something this container can debug.
  it "sends none of the sampling parameters claude-opus-5 refuses" do
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(client.request.keys & [ :temperature, :top_p, :top_k ]).to be_empty
  end

  # The ceiling covers the thinking as well as the answer, and thinking is on
  # by default. Sized too tightly it does not truncate the reasoning, it
  # truncates the JSON the reasoning was leading up to.
  it "leaves room for the thinking that is counted against the answer" do
    client = FakeAnthropic.new(text: one_story)

    Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(client.request[:max_tokens]).to be >= 16_000
  end

  it "returns the stories the model wrote" do
    client = FakeAnthropic.new(text: one_story)

    copy = Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(copy.stories).to eq(JSON.parse(one_story, symbolize_names: true)[:stories])
  end

  it "records what the edition cost to write" do
    client = FakeAnthropic.new(text: one_story, input_tokens: 61_204, output_tokens: 3_812)

    copy = Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(copy.input_tokens).to eq(61_204)
    expect(copy.output_tokens).to eq(3_812)
  end

  # The model that answered rather than the one that was asked for, so an
  # edition records what actually wrote it.
  it "records the model that answered" do
    client = FakeAnthropic.new(text: one_story)

    copy = Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(copy.model).to eq("claude-opus-5")
  end

  it "records the prompt version the edition was written from" do
    prompt = Edition::Prompt.new(newsletters)
    client = FakeAnthropic.new(text: one_story)

    copy = Edition::Draft.new(prompt, client: client).write

    expect(copy.prompt_version).to eq(prompt.version)
  end

  # Kept whole rather than as the story text alone: a bad edition is read back
  # months later, and the stop reason and the token counts are half of what
  # says why it came out the way it did.
  it "keeps the whole response for reading back later" do
    client = FakeAnthropic.new(text: one_story)

    copy = Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write

    expect(JSON.parse(copy.raw_response)).to include("stop_reason" => "end_turn")
  end

  # A declined request is an HTTP 200 with nothing in it, so anything that
  # reads the content first raises about a nil rather than about the refusal.
  it "raises when a classifier declines the request" do
    client = FakeAnthropic.new(stop_reason: :refusal)

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Refused)
  end

  it "raises when the answer stopped before the JSON closed" do
    client = FakeAnthropic.new(text: %({"stories":[), stop_reason: :max_tokens)

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Truncated)
  end

  it "reports a rate limit as the API failing to answer" do
    client = FakeAnthropic.new(error: FakeAnthropic.api_error(429))

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Unavailable)
  end

  it "reports an unreachable API the same way" do
    client = FakeAnthropic.new(error: Anthropic::Errors::APIConnectionError.new(url: FakeAnthropic::URL))

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Unavailable)
  end

  # Separated from the two above because the answer is different: nothing to
  # wait for, something to fix.
  it "reports a refused request as our own bug" do
    client = FakeAnthropic.new(error: FakeAnthropic.api_error(400))

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Rejected)
  end

  # The SDK already retries 429s and 5xx with backoff. A loop around it would
  # multiply out to a dozen attempts at a window of sixty thousand tokens.
  it "leaves retrying to the SDK" do
    client = FakeAnthropic.new(error: FakeAnthropic.api_error(429))

    expect { Edition::Draft.new(Edition::Prompt.new(newsletters), client: client).write }
      .to raise_error(Edition::Draft::Unavailable)
    expect(client.messages.requests.length).to eq(1)
  end

  # A constant read at class load would take the whole app down on boot, this
  # suite included. Read where it is used, a missing key is one job failing
  # with the name of the variable it wanted.
  it "looks the API key up where it uses it, not when it is built" do
    key = ENV.delete("ANTHROPIC_API_KEY")
    draft = Edition::Draft.new(Edition::Prompt.new(newsletters))

    expect { draft.write }.to raise_error(KeyError, /ANTHROPIC_API_KEY/)

    ENV["ANTHROPIC_API_KEY"] = key
  end
end
