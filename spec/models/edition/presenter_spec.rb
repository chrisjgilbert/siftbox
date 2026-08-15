require "rails_helper"

RSpec.describe Edition::Presenter do
  it "heads the edition with its number and the day it covers" do
    edition = build_stubbed(:edition, number: 1, published_on: Date.new(2026, 8, 11))

    expect(Edition::Presenter.new(edition).masthead).to eq("No. 1 · Tuesday 11 August")
  end

  # The archive prints the two halves in their own columns, because the day
  # covered is what the list is ordered by and what a reader scans for.
  it "names the edition by its number" do
    edition = build_stubbed(:edition, number: 4)

    expect(Edition::Presenter.new(edition).number).to eq("No. 4")
  end

  it "dates the edition by the day it covers" do
    edition = build_stubbed(:edition, published_on: Date.new(2026, 8, 11))

    expect(Edition::Presenter.new(edition).date).to eq("Tuesday 11 August")
  end

  it "reads the sections in the order the page prints them" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::READING_LIST, position: 1)
    create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY, position: 2)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD, position: 3)

    sections = Edition::Presenter.new(edition).sections

    expect(sections.map(&:name)).to eq([ "lead", "briefly", "reading_list" ])
  end

  it "heads each section with its own name" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::READING_LIST)

    sections = Edition::Presenter.new(edition).sections

    expect(sections.map(&:heading)).to eq([ "The reading list" ])
  end

  # A window with no evergreen item renders no reading list at all, rather
  # than a heading over nothing.
  it "drops a section the edition has nothing for" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD)

    sections = Edition::Presenter.new(edition).sections

    expect(sections.map(&:name)).to eq([ "lead" ])
  end

  it "keeps each section's stories in the order the editor filed them" do
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "Second", position: 2)
    create(:edition_story, edition: edition, headline: "First", position: 1)

    sections = Edition::Presenter.new(edition).sections

    expect(sections.sole.stories.map(&:headline)).to eq([ "First", "Second" ])
  end

  it "has no sections at all for an edition with no stories" do
    edition = create(:edition)

    expect(Edition::Presenter.new(edition).sections).to be_empty
  end

  it "answers to the edition's own address" do
    edition = create(:edition)

    expect(Edition::Presenter.new(edition).to_param).to eq(edition.to_param)
  end
end
