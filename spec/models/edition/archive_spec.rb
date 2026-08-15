require "rails_helper"

RSpec.describe Edition::Archive do
  it "lists the editions newest first" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 12))

    editions = Edition::Archive.new.editions

    expect(editions.map(&:masthead)).to eq(
      [ "No. 2 · Wednesday 12 August", "No. 1 · Tuesday 11 August" ]
    )
  end

  # Numbering follows composition order and the archive sorts by the day
  # covered, so a backfilled edition reads No. 1, No. 3, No. 2. Decided in
  # docs/briefing-followups.md rather than open, and this is where it shows.
  it "files an edition composed late under the day it covers" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 13))
    create(:edition, number: 3, published_on: Date.new(2026, 8, 12))

    editions = Edition::Archive.new.editions

    expect(editions.map(&:masthead).last).to eq("No. 1 · Tuesday 11 August")
  end

  # Counted off the editions already loaded rather than a second query, the
  # way Feed#issue_count is, so the figure at the head of the list cannot
  # disagree with the list under it.
  it "counts the editions it lists" do
    create(:edition)
    create(:edition)

    expect(Edition::Archive.new.count).to eq(2)
  end

  it "has nothing to list before the first edition is published" do
    expect(Edition::Archive.new).not_to be_any
  end

  it "has something to list once an edition is published" do
    create(:edition)

    expect(Edition::Archive.new).to be_any
  end
end
