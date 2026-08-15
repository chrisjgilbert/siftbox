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

  # Two runs at once read the same maximum and both allocate the same number.
  # The unique index is what makes that a failed insert rather than two
  # editions numbered 4, so whatever composes has to expect it.
  it "refuses a duplicate number at the database as well as in Ruby" do
    create(:edition, number: 4, published_on: Date.new(2026, 8, 11))

    second = build(:edition, number: 4, published_on: Date.new(2026, 8, 12))

    expect { second.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "starts its numbering at No. 1" do
    expect(Edition.next_number).to eq(1)
  end

  # The highest number, not the count and not the newest edition's: a gap left
  # by a failed insert must not be handed out to two editions.
  it "numbers the next edition above every number so far" do
    create(:edition, number: 9, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 3, published_on: Date.new(2026, 8, 12))

    expect(Edition.next_number).to eq(10)
  end

  it "has no watermark before the first edition" do
    expect(Edition.watermark).to be_nil
  end

  it "marks the watermark where the newest window closed" do
    create(:edition, published_on: Date.new(2026, 8, 11), window_ended_at: Time.utc(2026, 8, 11, 6))
    create(:edition, published_on: Date.new(2026, 8, 12), window_ended_at: Time.utc(2026, 8, 12, 6))

    expect(Edition.watermark).to eq(Time.utc(2026, 8, 12, 6))
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

  it "takes its stories' citations with it when destroyed" do
    edition = create(:edition)
    create(:edition_citation, story: create(:edition_story, edition: edition))

    edition.destroy

    expect(Edition::Citation.count).to eq(0)
  end

  # Story's uniqueness validation reads the table, so two unsaved stories both
  # claiming position 3 pass it and collide on the index instead.
  it "refuses two stories at the same position before either is saved" do
    edition = build(:edition)
    edition.stories.build(attributes_for(:edition_story, position: 3))
    edition.stories.build(attributes_for(:edition_story, position: 3))

    expect(edition).not_to be_valid
  end

  it "allows stories at different positions" do
    edition = build(:edition)
    edition.stories.build(attributes_for(:edition_story, position: 1))
    edition.stories.build(attributes_for(:edition_story, position: 2))

    expect(edition).to be_valid
  end
end
