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
end
