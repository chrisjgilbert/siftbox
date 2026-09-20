require "rails_helper"

RSpec.describe Edition::Archive do
  def failure_on(morning)
    Edition::Gap.failed(Edition::Window.new(morning), "the model declined")
  end

  def quiet_morning_on(morning)
    Edition::Gap.empty(Edition::Window.new(morning))
  end

  it "lists the editions newest first" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 12))

    expect(Edition::Archive.new.rows.map(&:number)).to eq([ "No. 2", "No. 1" ])
  end

  # Numbering follows composition order and the archive sorts by the day
  # covered, so a backfilled edition reads No. 1, No. 3, No. 2. Decided in
  # docs/briefing-followups.md rather than open, and this is where it shows.
  it "files an edition composed late under the day it covers" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 13))
    create(:edition, number: 3, published_on: Date.new(2026, 8, 12))

    expect(Edition::Archive.new.rows.map(&:number).last).to eq("No. 1")
  end

  # Counted off the rows already loaded rather than a second query, the way
  # Feed#issue_count is, so the figure at the head of the list cannot disagree
  # with the list under it.
  it "counts the editions it lists" do
    create(:edition)
    create(:edition)

    expect(Edition::Archive.new.count).to eq(2)
  end

  it "has nothing to list before the first morning" do
    expect(Edition::Archive.new).not_to be_any
  end

  it "has something to list once an edition is published" do
    create(:edition)

    expect(Edition::Archive.new).to be_any
  end

  # The reader is owed an explanation for a morning that should have had an
  # edition and does not. It stays in the list permanently: an archive that
  # quietly closed over its own failures is the thing this exists to prevent.
  it "lists a morning composition failed on" do
    failure_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new.rows.map(&:date)).to eq([ "Saturday 15 August" ])
  end

  it "has something to list when the only morning so far failed" do
    failure_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new).to be_any
  end

  it "files a failure among the editions by the day it covered" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 14))
    failure_on(Time.zone.local(2026, 8, 15, 7))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 16))

    expect(Edition::Archive.new.rows.map(&:number))
      .to eq([ "No. 2", "No edition", "No. 1" ])
  end

  # The caption over the list says how many editions there are, so it counts
  # editions. A failure is a row without one, and counting it would have the
  # page claim an edition a reader cannot open.
  it "leaves a failure out of the count" do
    create(:edition, published_on: Date.new(2026, 8, 14))
    failure_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new.count).to eq(1)
  end

  # A morning nothing arrived on needs no explanation, and a list of quiet
  # days is not an archive of anything.
  it "leaves a morning nothing arrived on out of the list" do
    quiet_morning_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new).not_to be_any
  end

  # A morning can be composed again by hand after an outage. The failure is
  # then history rather than news, and listing it beside the edition it was
  # standing in for would have the archive contradict itself on one line.
  it "drops a failure once the morning has an edition after all" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 15))
    failure_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new.rows.map(&:number)).to eq([ "No. 1" ])
  end

  # Each row picks the template that draws it, so the view never asks which
  # kind it is holding. A failure's template carries no link.
  it "draws an edition and a failure through templates of their own" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 14))
    failure_on(Time.zone.local(2026, 8, 15, 7))

    expect(Edition::Archive.new.rows.map(&:to_partial_path))
      .to eq([ "editions/gap_row", "editions/row" ])
  end
end
