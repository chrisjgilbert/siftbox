require "rails_helper"

RSpec.describe EditionRegeneration do
  # The answer a model would send for these newsletters: one story citing
  # every one of them, which is what the editor's completeness check demands.
  # Built from whatever set the example expects to be sent, so an edition that
  # composes at all is proof the editor was handed exactly that set — a
  # missing id fails the check as loudly as an invented one.
  def answer(newsletters)
    {
      stories: [ {
        headline: "Figma filed", body: "The S-1 landed.", section: "lead",
        newsletter_ids: newsletters.map(&:id)
      } ]
    }.to_json
  end

  # An edition the way composition leaves one: stories, citations, and the
  # provenance of the run that wrote it.
  def published(newsletters, **attributes)
    edition = create(:edition, **attributes)
    story = create(:edition_story, edition: edition, position: 1)
    newsletters.each do |newsletter|
      create(:edition_citation, story: story, newsletter: newsletter)
    end

    edition
  end

  # One edition where there was one. The unique indexes on number and
  # published_on leave no other option: a regeneration cannot sit beside the
  # edition it regenerates, so it is written over it.
  it "writes the new edition over the one it was asked to rewrite" do
    newsletter = create(:newsletter)
    edition = published([ newsletter ])

    EditionRegeneration
      .new(edition, client: FakeAnthropic.new(text: answer([ newsletter ]))).rewrite

    expect(Edition.count).to eq(1)
    expect(Edition.first.id).not_to eq(edition.id)
  end

  # Same edition, rewritten — not a new one. The masthead is what the reader
  # identifies it by, and No. 7 for the 14th has to stay No. 7 for the 14th.
  it "keeps the number and the day the edition was published under" do
    newsletter = create(:newsletter)
    edition = published([ newsletter ], number: 7, published_on: Date.new(2026, 8, 14))

    rewritten = EditionRegeneration
      .new(edition, client: FakeAnthropic.new(text: answer([ newsletter ]))).rewrite

    expect(rewritten).to have_attributes(number: 7, published_on: Date.new(2026, 8, 14))
  end

  # The one attribute a regeneration must not move. window_ended_at is the
  # watermark the next real composition starts from, so a rewrite that reset
  # it to now would make tomorrow's edition skip everything that arrived in
  # between — or, moved the other way, cover it twice.
  it "leaves the watermark exactly where the edition left it" do
    closed_at = Time.zone.parse("2026-08-14 07:00:00")
    newsletter = create(:newsletter)
    edition = published([ newsletter ], window_ended_at: closed_at)

    EditionRegeneration
      .new(edition, client: FakeAnthropic.new(text: answer([ newsletter ]))).rewrite

    expect(Edition.watermark).to eq(closed_at)
  end

  # The whole reason the citations are the window rather than the dates. A
  # newsletter released out of the confirmation pen was cited by the edition
  # whose window it was released into, and its received_at sits well outside
  # that edition's recorded window; a newsletter that arrived inside those
  # dates but after the edition closed was never in it. Re-running the range
  # would swap one for the other, and the completeness check would fail the
  # answer either way.
  it "composes from the newsletters the edition cited, not from the dates it recorded" do
    released = create(:newsletter, received_at: 3.weeks.ago)
    create(:newsletter, received_at: 90.minutes.ago)
    edition = published(
      [ released ], window_started_at: 2.hours.ago, window_ended_at: 1.hour.ago
    )

    rewritten = EditionRegeneration
      .new(edition, client: FakeAnthropic.new(text: answer([ released ]))).rewrite

    expect(rewritten.stories.flat_map(&:newsletters)).to eq([ released ])
  end

  # Whole rows, because Edition::Prompt writes the prompt out of body_html.
  # A column list here would send the model an edition's worth of subject
  # lines, the same trap Edition::Window's newsletters comment names.
  it "reads the cited newsletters with the bodies the prompt is written from" do
    newsletter = create(:newsletter, body_html: "<p>The S-1 landed.</p>")
    edition = published([ newsletter ])

    sources = EditionRegeneration.new(edition).sources

    expect(sources.map(&:body_html)).to eq([ "<p>The S-1 landed.</p>" ])
  end

  # In the order the first composition read them, so the second reads the
  # same window the same way round.
  it "reads the cited newsletters oldest first" do
    newer = create(:newsletter, received_at: 1.hour.ago)
    older = create(:newsletter, received_at: 5.hours.ago)
    edition = published([ newer, older ])

    sources = EditionRegeneration.new(edition).sources

    expect(sources).to eq([ older, newer ])
  end

  # The provenance is of the run that wrote the words. Keeping the old row's
  # prompt version beside new copy would make the one column that says how an
  # edition came to read this way a lie.
  it "records the provenance of the rewrite rather than the edition's own" do
    newsletter = create(:newsletter)
    edition = published([ newsletter ], input_tokens: 11, prompt_version: "0")
    client = FakeAnthropic.new(text: answer([ newsletter ]), input_tokens: 4200)

    rewritten = EditionRegeneration.new(edition, client: client).rewrite

    expect(rewritten)
      .to have_attributes(input_tokens: 4200, prompt_version: Edition::Prompt::VERSION)
  end

  # The destroy and the composition are one transaction, so a model that
  # cannot answer costs the reader nothing: the edition they already have
  # survives a failed rewrite intact.
  it "keeps the published edition when the model cannot answer" do
    newsletter = create(:newsletter)
    edition = published([ newsletter ])
    client = FakeAnthropic.new(error: FakeAnthropic.api_error(529))

    expect { EditionRegeneration.new(edition, client: client).rewrite }
      .to raise_error(Edition::Draft::Unavailable)

    expect(Edition.find_by(id: edition.id)).to eq(edition)
  end

  # An edition citing nothing is the vacuous-completeness gap wearing a
  # different hat: the editor would accept any answer at all over an empty
  # set, so rewriting from one would replace a published edition with an
  # empty one. Nothing composition builds looks like this; a hand-built row
  # does.
  it "refuses to rewrite an edition that cites no newsletters" do
    edition = create(:edition)

    expect { EditionRegeneration.new(edition).rewrite }
      .to raise_error(EditionRegeneration::Empty)

    expect(Edition.find_by(id: edition.id)).to eq(edition)
  end
end
