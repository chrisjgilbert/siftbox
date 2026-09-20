require "rails_helper"

RSpec.describe Edition::Script do
  it "opens on the edition's number and the day it covers" do
    edition = build_stubbed(:edition, number: 14, published_on: Date.new(2026, 8, 11))

    expect(Edition::Script.new(edition).text)
      .to start_with("Edition 14, Tuesday 11 August.")
  end

  # "No. 14" is what the masthead prints and it is the one string on the page
  # that cannot be spoken as it stands: read aloud, the abbreviation is the
  # word "no".
  it "says the number as a number rather than as the masthead abbreviates it" do
    edition = build_stubbed(:edition, number: 14)

    expect(Edition::Script.new(edition).text).not_to include("No.")
  end

  it "reads the sections in the order the page prints them" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::READING_LIST, position: 1)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD, position: 2)

    expect(Edition::Script.new(edition).text)
      .to match(/Lead stories\..*The reading list\./m)
  end

  it "speaks each section's own heading" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY)

    expect(Edition::Script.new(edition).text).to include("Briefly.")
  end

  it "speaks a story's headline before its body" do
    edition = create(:edition)
    create(:edition_story, edition: edition,
      headline: "Ruby 3.4 ships a rewritten parser", body: "Both newsletters lead with it.")

    expect(Edition::Script.new(edition).text)
      .to include("Ruby 3.4 ships a rewritten parser.\n\nBoth newsletters lead with it.")
  end

  # A Briefly line leaves the headline column at its "" default, and there is
  # nothing to announce before the sentence itself.
  it "speaks a story with no headline as its body alone" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY,
      headline: "", body: "Postgres 18 adds skip scan.")

    expect(Edition::Script.new(edition).text)
      .to include("Briefly.\n\nPostgres 18 adds skip scan.")
  end

  # The whole bet of the first version: the editor's prose is already plain
  # sentences with the attribution inside them, so it is spoken as written
  # rather than rewritten for the ear.
  it "leaves the editor's prose exactly as it was written" do
    edition = create(:edition)
    written = "Money Stuff and The Diff both read the S-1; Levine focuses on the footnotes."
    create(:edition_story, edition: edition, body: written)

    expect(Edition::Script.new(edition).text).to include(written)
  end

  # The citation line under a story is an index of sender names, which is
  # furniture for the eye and a list of proper nouns read aloud. The link is
  # how a claim gets checked, and checking happens on the page.
  it "says nothing about the sources a story cites" do
    edition = create(:edition)
    story = create(:edition_story, edition: edition, body: "The filing landed on Tuesday.")
    create(:edition_citation, story: story,
      newsletter: create(:newsletter, sender_name: "Query Plan Weekly"))

    expect(Edition::Script.new(edition).text).not_to include("Query Plan Weekly")
  end

  # Headlines are written as headlines, so most carry no final stop. Without
  # one a synthesiser runs the headline into the first sentence of the body.
  it "closes a headline that carries no sentence ending of its own" do
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "Figma filed")

    expect(Edition::Script.new(edition).text).to include("Figma filed.")
  end

  it "leaves a headline that already ends a sentence alone" do
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "Who owns the parser?")

    expect(Edition::Script.new(edition).text).to include("Who owns the parser?\n")
  end

  it "is the masthead alone for an edition with no stories" do
    edition = create(:edition, number: 3, published_on: Date.new(2026, 8, 11))

    expect(Edition::Script.new(edition).text).to eq("Edition 3, Tuesday 11 August.")
  end
end
