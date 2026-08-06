require "rails_helper"

RSpec.describe Feed do
  it "puts today's newsletters in the first group" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 2.hours.ago)

      expect(Feed.new.groups.first.label).to eq("Today")
    end
  end

  it "labels today's group with the full date" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 2.hours.ago)

      expect(Feed.new.groups.first.sublabel).to eq("Thursday 6 August")
    end
  end

  it "puts yesterday's newsletters in their own group" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 1.day.ago)

      expect(Feed.new.groups.map(&:label)).to eq([ "Yesterday" ])
    end
  end

  it "puts the rest of the week under Earlier" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 3.days.ago)

      expect(Feed.new.groups.map(&:label)).to eq([ "Earlier" ])
    end
  end

  it "labels the Earlier group This week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 3.days.ago)

      expect(Feed.new.groups.first.sublabel).to eq("This week")
    end
  end

  it "leaves out a group that has no newsletters" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 2.hours.ago)
      create(:newsletter, received_at: 3.days.ago)

      expect(Feed.new.groups.map(&:label)).to eq([ "Today", "Earlier" ])
    end
  end

  it "orders newsletters newest first inside a group" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      earlier = create(:newsletter, received_at: 5.hours.ago)
      later = create(:newsletter, received_at: 1.hour.ago)

      expect(Feed.new.groups.first.newsletters).to eq([ later, earlier ])
    end
  end

  it "excludes newsletters older than the window the end-of-list copy claims" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 8.days.ago)

      expect(Feed.new.groups).to be_empty
    end
  end

  it "counts the unread newsletters for the filter label" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 1.hour.ago, read_at: nil)
      create(:newsletter, received_at: 2.hours.ago, read_at: 1.minute.ago)

      expect(Feed.new.unread_count).to eq(1)
    end
  end

  it "shows only unread newsletters when filtered to unread" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      unread = create(:newsletter, received_at: 1.hour.ago, read_at: nil)
      create(:newsletter, received_at: 2.hours.ago, read_at: 1.minute.ago)

      expect(Feed.new(filter: "unread").groups.first.newsletters).to eq([ unread ])
    end
  end

  it "counts unread newsletters even while filtered to unread" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      create(:newsletter, received_at: 1.hour.ago, read_at: nil)

      expect(Feed.new(filter: "unread").unread_count).to eq(1)
    end
  end

  it "is empty when nothing has arrived" do
    expect(Feed.new.groups).to be_empty
  end
end
