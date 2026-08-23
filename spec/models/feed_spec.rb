require "rails_helper"

RSpec.describe Feed do
  it "puts today's newsletters in the first group" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.hours.ago)

    expect(Feed.new.groups.first.label).to eq("Today")
  end

  it "labels today's group with the full date" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.hours.ago)

    expect(Feed.new.groups.first.sublabel).to eq("Thursday 6 August")
  end

  it "puts yesterday's newsletters in their own group" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 1.day.ago)

    expect(Feed.new.groups.map(&:label)).to eq([ "Yesterday" ])
  end

  it "puts the rest of the week under Earlier" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 3.days.ago)

    expect(Feed.new.groups.map(&:label)).to eq([ "Earlier" ])
  end

  it "labels the Earlier group This week" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 3.days.ago)

    expect(Feed.new.groups.first.sublabel).to eq("This week")
  end

  it "leaves out a group that has no newsletters" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.hours.ago)
    create(:newsletter, received_at: 3.days.ago)

    expect(Feed.new.groups.map(&:label)).to eq([ "Today", "Earlier" ])
  end

  it "orders newsletters newest first inside a group" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 5.hours.ago, subject: "Earlier one")
    create(:newsletter, received_at: 1.hour.ago, subject: "Later one")

    subjects = Feed.new.groups.first.items.map(&:subject)

    expect(subjects).to eq([ "Later one", "Earlier one" ])
  end

  # The archive answers "did this morning's Money Stuff arrive?", and a
  # Substack confirmation sitting in the pen is not an answer to that.
  it "leaves out mail held as a subscription confirmation" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.hours.ago, held_at: 1.hour.ago)

    expect(Feed.new.item_count).to eq(0)
  end

  it "leaves out a confirmation that was dismissed" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 3.hours.ago, held_at: 2.hours.ago, dismissed_at: 1.hour.ago)

    expect(Feed.new.item_count).to eq(0)
  end

  # A misfire put real mail in the pen; releasing it has to put it back where
  # it would have been, not merely stop hiding it from the next edition.
  it "shows a newsletter released back out of the pen" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 3.hours.ago, held_at: 2.hours.ago, released_at: 1.hour.ago)

    expect(Feed.new.item_count).to eq(1)
  end

  it "excludes newsletters older than the window the end-of-list copy claims" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 8.days.ago)

    expect(Feed.new.groups).to be_empty
  end

  it "puts a newsletter received at exactly midnight in one group only" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: Date.yesterday.beginning_of_day)

    expect(Feed.new.groups.map(&:label)).to eq([ "Yesterday" ])
  end

  it "shows a newsletter dated in the future rather than hiding it" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.days.from_now)

    expect(Feed.new.groups.first.label).to eq("Today")
  end

  it "counts the same rows it renders" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 2.days.from_now)

    rendered = Feed.new.groups.sum { |group| group.items.length }

    expect(rendered).to eq(Feed.new.item_count)
  end

  it "hands the view presenters rather than records" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 1.hour.ago, sender_name: "Ruby Weekly")

    expect(Feed.new.groups.first.items.first.sender).to eq("Ruby Weekly")
  end

  it "is empty when nothing has arrived" do
    expect(Feed.new.groups).to be_empty
  end

  # Continuously across the whole feed rather than restarting per group, so
  # the numbers read as an index rather than as three short lists.
  it "numbers rows continuously across the groups" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 1.hour.ago)
    create(:newsletter, received_at: 1.day.ago)
    create(:newsletter, received_at: 3.days.ago)

    numbers = Feed.new.groups.flat_map { |group| group.items.map(&:number) }

    expect(numbers).to eq([ "01", "02", "03" ])
  end

  it "numbers rows newest first inside a group" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 5.hours.ago, subject: "Earlier one")
    create(:newsletter, received_at: 1.hour.ago, subject: "Later one")

    first = Feed.new.groups.first.items.first

    expect(first).to have_attributes(number: "01", subject: "Later one")
  end

  it "counts the items in the feed for the end-of-feed line" do
    travel_to Time.zone.parse("2026-08-06 18:00")

    create(:newsletter, received_at: 1.hour.ago)
    create(:newsletter, received_at: 3.days.ago)

    expect(Feed.new.item_count).to eq(2)
  end

  it "lists blog posts alongside newsletters" do
    create(:newsletter, subject: "Ruby 3.4 lands", received_at: 2.hours.ago)
    create(:blog_post, title: "Why your index is not used", received_at: 1.hour.ago)

    rows = Feed.new.groups.flat_map(&:items)

    expect(rows.map(&:subject))
      .to eq([ "Why your index is not used", "Ruby 3.4 lands" ])
  end

  # Every ordering in this app breaks ties on the id, because arrival times
  # carry whole seconds and a batch lands on one instant. That stops working
  # across two tables — newsletter 5 and post 5 are not comparable — so the
  # order needs a third key, or tied rows swap places between page loads and
  # the continuous numbering swaps with them.
  it "orders a newsletter and a post that arrived on the same instant the same way twice" do
    landed = 1.hour.ago
    create(:newsletter, subject: "A newsletter", received_at: landed)
    create(:blog_post, title: "A post", received_at: landed)

    first = Feed.new.groups.flat_map(&:items).map(&:subject)
    second = Feed.new.groups.flat_map(&:items).map(&:subject)

    expect(first).to eq(second)
  end

  it "counts posts in the end-of-feed tally" do
    create(:newsletter, received_at: 1.hour.ago)
    create(:blog_post, received_at: 1.hour.ago)

    expect(Feed.new.item_count).to eq(2)
  end
end
