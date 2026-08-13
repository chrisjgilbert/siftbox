require "rails_helper"

RSpec.describe Edition do
  it "requires a sequence number" do
    expect(build(:edition)).to validate_presence_of(:number)
  end

  it "requires a publication date" do
    expect(build(:edition)).to validate_presence_of(:published_on)
  end

  it "requires a publication time" do
    expect(build(:edition)).to validate_presence_of(:published_at)
  end

  it "requires a window start" do
    expect(build(:edition)).to validate_presence_of(:window_started_at)
  end

  it "requires a window end" do
    expect(build(:edition)).to validate_presence_of(:window_ended_at)
  end

  it "refuses a number another edition already carries" do
    create(:edition, number: 7, published_on: Date.new(2026, 8, 11))

    edition = build(:edition, number: 7, published_on: Date.new(2026, 8, 12))

    expect(edition).not_to be_valid
  end

  it "refuses a date another edition already covers" do
    create(:edition, number: 7, published_on: Date.new(2026, 8, 11))

    edition = build(:edition, number: 8, published_on: Date.new(2026, 8, 11))

    expect(edition).not_to be_valid
  end

  it "orders newest first" do
    older = create(:edition, published_on: Date.new(2026, 8, 11))
    newer = create(:edition, published_on: Date.new(2026, 8, 12))

    expect(Edition.newest_first).to eq([ newer, older ])
  end

  # A failed run retries, so an edition can be written after the one that
  # follows it. It is still the earlier day's edition, and the archive has to
  # read in date order rather than in the order the editor got round to it.
  it "orders an edition composed late by the day it covers" do
    late = create(:edition, published_on: Date.new(2026, 8, 12), published_at: Time.utc(2026, 8, 13, 8))
    on_time = create(:edition, published_on: Date.new(2026, 8, 13), published_at: Time.utc(2026, 8, 13, 7))

    expect(Edition.newest_first).to eq([ on_time, late ])
  end

  it "finds the latest edition" do
    create(:edition, published_on: Date.new(2026, 8, 11))
    latest = create(:edition, published_on: Date.new(2026, 8, 12))

    expect(Edition.latest).to eq(latest)
  end

  it "has no latest edition before the first one is published" do
    expect(Edition.latest).to be_nil
  end

  it "keeps its stories in the order the editor put them in" do
    edition = create(:edition)
    second = create(:edition_story, edition: edition, position: 2)
    first = create(:edition_story, edition: edition, position: 1)

    expect(edition.stories).to eq([ first, second ])
  end

  it "hands out its lead stories" do
    edition = create(:edition)
    lead = create(:edition_story, edition: edition, section: Edition::Story::LEAD)
    create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY)

    expect(edition.lead_stories).to eq([ lead ])
  end

  it "hands out its briefly items" do
    edition = create(:edition)
    briefly = create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD)

    expect(edition.briefly).to eq([ briefly ])
  end

  it "hands out its reading list" do
    edition = create(:edition)
    entry = create(:edition_story, edition: edition, section: Edition::Story::READING_LIST)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD)

    expect(edition.reading_list).to eq([ entry ])
  end

  it "has a reading list when the window held an evergreen item" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::READING_LIST)

    expect(edition).to be_reading_list
  end

  it "has no reading list when the window held nothing but news" do
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD)

    expect(edition).not_to be_reading_list
  end

  it "takes its stories with it when destroyed" do
    edition = create(:edition)
    create(:edition_story, edition: edition)

    edition.destroy

    expect(Edition::Story.count).to eq(0)
  end
end
