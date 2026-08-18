require "rails_helper"

RSpec.describe EditionTranscript do
  # Positions are unique within an edition and the transcript prints them, so
  # they are counted off the edition rather than passed in and kept in step by
  # hand.
  def story_in(edition, section, headline: "Halcyon relicenses Tessera", body: "The S-1 landed.")
    create(
      :edition_story, edition: edition, section: section, headline: headline,
      body: body, position: edition.stories.count + 1
    )
  end

  def cite(story, newsletter)
    create(:edition_citation, story: story, newsletter: newsletter)
  end

  def transcript(edition, newsletters)
    EditionTranscript.new(edition.reload, newsletters).text
  end

  it "heads the edition with its number and the day it covers" do
    edition = create(:edition, number: 4, published_on: Date.new(2026, 8, 11))

    printed = transcript(edition, [])

    expect(printed).to include("NO. 4 · TUESDAY 11 AUGUST")
  end

  # The window is what a backtest is choosing between, so it is printed at the
  # top where the judgement about the edition below it starts.
  it "prints the window it was composed from" do
    edition = create(
      :edition, window_started_at: Time.zone.local(2026, 8, 10, 7, 0),
      window_ended_at: Time.zone.local(2026, 8, 11, 7, 0)
    )

    printed = transcript(edition, [])

    expect(printed).to include("10 AUG 07:00 → 11 AUG 07:00")
  end

  it "prints the model and the prompt that wrote it" do
    edition = create(:edition, editor_model: "claude-opus-5", prompt_version: "1")

    printed = transcript(edition, [])

    expect(printed).to include("CLAUDE-OPUS-5 · PROMPT 1")
  end

  it "prints what the edition cost to write" do
    edition = create(:edition, input_tokens: 61_000, output_tokens: 7_400)

    printed = transcript(edition, [])

    expect(printed).to include("$0.49")
  end

  it "prints a lead story under the lead heading" do
    edition = create(:edition)
    story_in(edition, Edition::Story::LEAD, headline: "Halcyon relicenses Tessera")

    printed = transcript(edition, [])

    expect(printed).to match(/LEAD STORIES.*Halcyon relicenses Tessera/m)
  end

  it "prints the story as the editor wrote it" do
    edition = create(:edition)
    story_in(edition, Edition::Story::BRIEFLY, body: "Corvid 4.2 shipped on Monday.")

    printed = transcript(edition, [])

    expect(printed).to include("Corvid 4.2 shipped on Monday.")
  end

  it "numbers each story with the position it holds in the edition" do
    edition = create(:edition)
    story_in(edition, Edition::Story::LEAD)
    story_in(edition, Edition::Story::LEAD, headline: "Corvid 4.2 adds skiplists")

    printed = transcript(edition, [])

    expect(printed).to match(/2\s+Corvid 4\.2 adds skiplists/)
  end

  # Attribution is the second of Milestone 0's five checks, and it is made by
  # reading the story against the mail it names — so the citation carries the
  # sender, the subject and the id the raw response can be grepped for.
  it "names the newsletters a story cites, with their ids" do
    edition = create(:edition)
    levine = create(:newsletter, sender_name: "Money Stuff", subject: "The Figma S-1")
    cite(story_in(edition, Edition::Story::LEAD), levine)

    printed = transcript(edition, [ levine ])

    expect(printed).to include("[#{levine.id}] Money Stuff — The Figma S-1")
  end

  # The same rule the edition page follows: a window with no evergreen items
  # gets no heading rather than a heading over nothing.
  it "leaves out the reading list when nothing landed on it" do
    edition = create(:edition)
    story_in(edition, Edition::Story::LEAD)

    printed = transcript(edition, [])

    expect(printed).not_to include("THE READING LIST")
  end

  it "prints the reading list when something did" do
    edition = create(:edition)
    story_in(edition, Edition::Story::READING_LIST, headline: "Consistent hashing")

    printed = transcript(edition, [])

    expect(printed).to match(/THE READING LIST.*Consistent hashing/m)
  end

  # Read in a terminal, so the prose is folded rather than left to the window
  # to wrap wherever it happens to end.
  it "folds a long story to the width of the page" do
    edition = create(:edition)
    story_in(edition, Edition::Story::LEAD, body: "Halcyon shipped it. " * 40)

    printed = transcript(edition, [])

    expect(printed.lines.map(&:chomp).map(&:length).max).to be <= EditionTranscript::WIDTH
  end

  # Coverage is the third of Milestone 0's checks and the one a reader cannot
  # make by reading the edition alone: it is about what is not in it.
  it "lists every newsletter in the window against the stories citing it" do
    edition = create(:edition)
    levine = create(:newsletter, sender_name: "Money Stuff")
    cite(story_in(edition, Edition::Story::LEAD), levine)
    cite(story_in(edition, Edition::Story::BRIEFLY), levine)

    printed = transcript(edition, [ levine ])

    expect(printed).to match(/\[#{levine.id}\] Money Stuff\D+2 stories/)
  end

  it "says when a newsletter in the window was cited by nothing" do
    edition = create(:edition)
    orphan = create(:newsletter, sender_name: "Offscreen")

    printed = transcript(edition, [ orphan ])

    expect(printed).to match(/\[#{orphan.id}\] Offscreen\D+no story/)
  end

  it "counts the window it was given" do
    edition = create(:edition)
    newsletters = create_list(:newsletter, 3)

    printed = transcript(edition, newsletters)

    expect(printed).to include("3 NEWSLETTERS")
  end
end
