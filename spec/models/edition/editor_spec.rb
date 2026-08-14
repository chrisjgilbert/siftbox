require "rails_helper"

RSpec.describe Edition::Editor do
  # The answer the model would have sent, in the shape Edition::Prompt's schema
  # asks for. Written out here rather than through a factory because it is not
  # a record — it is the one thing this class is built to distrust, and a spec
  # that could not write a bad one could not test the checking.
  def answer(*stories)
    { stories: stories }.to_json
  end

  def story(cites:, section: "lead", headline: "Figma filed", body: "The S-1 landed.")
    { headline: headline, body: body, section: section, newsletter_ids: cites }
  end

  # Persisted rather than built: citations carry a foreign key to newsletters,
  # so a composition against stubbed newsletters would fail on the constraint
  # rather than on anything this class did.
  def newsletter(subject: "Money Stuff")
    create(:newsletter, subject: subject)
  end

  def compose(newsletters, client)
    Edition::Editor.new(build(:edition), newsletters, client: client).compose
  end

  it "writes a story for each one the model answered" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(
      story(cites: [ source.id ], headline: "Figma filed"),
      story(cites: [ source.id ], headline: "Rates held")
    ))

    compose([ source ], client)

    expect(Edition.last.stories.map(&:headline)).to eq([ "Figma filed", "Rates held" ])
  end

  it "writes each story's body as the model wrote it" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], body: "Levine read the filing."))
    )

    compose([ source ], client)

    expect(Edition.last.stories.map(&:body)).to eq([ "Levine read the filing." ])
  end

  it "files a lead story in the leads" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ], section: "lead")))

    edition = compose([ source ], client)

    expect(edition.reload.lead_stories.map(&:headline)).to eq([ "Figma filed" ])
  end

  it "files a briefly line in Briefly" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], section: "briefly", headline: "Rates held"))
    )

    edition = compose([ source ], client)

    expect(edition.reload.briefly.map(&:headline)).to eq([ "Rates held" ])
  end

  it "files an evergreen item on the reading list" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], section: "reading_list", headline: "Consensus"))
    )

    edition = compose([ source ], client)

    expect(edition.reload.reading_list.map(&:headline)).to eq([ "Consensus" ])
  end

  # The model decides what order an edition reads in, across the sections as
  # well as within them, and the position column is where that order is kept.
  it "numbers the stories in the order the model answered them" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(
      story(cites: [ source.id ], section: "briefly"),
      story(cites: [ source.id ], section: "lead")
    ))

    compose([ source ], client)

    expect(Edition.last.stories.map(&:position)).to eq([ 1, 2 ])
  end

  it "cites the newsletters a story was written from" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id, diff.id ])))

    compose([ levine, diff ], client)

    expect(Edition.last.stories.first.newsletters).to contain_exactly(levine, diff)
  end

  # An answer naming one source twice is a duplicate, not a mistake about what
  # the story was written from — Edition::Story refuses to save it, so it is
  # taken down to one here rather than costing the day its edition.
  it "cites a newsletter once when the model named it twice" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id, source.id ])))

    compose([ source ], client)

    expect(Edition.last.stories.first.newsletters).to eq([ source ])
  end

  it "records the model that wrote the edition and the prompt it was given" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    compose([ source ], client)

    expect(Edition.last.editor_model).to eq("claude-opus-5")
    expect(Edition.last.prompt_version).to eq(Edition::Prompt::VERSION)
  end

  it "records what the edition cost" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ])), input_tokens: 61_000, output_tokens: 7_400
    )

    compose([ source ], client)

    expect(Edition.last.input_tokens).to eq(61_000)
    expect(Edition.last.output_tokens).to eq(7_400)
  end

  # Enough to read a bad edition back and to write it again after a prompt
  # change without asking every newsletter for its body a second time.
  it "keeps the whole answer for reading back later" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    compose([ source ], client)

    expect(Edition.last.raw_response).to include("Figma filed")
  end

  it "publishes the edition it was given" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    edition = compose([ source ], client)

    expect(edition).to be_persisted
  end
end
