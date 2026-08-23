require "rails_helper"

RSpec.describe Newsletter::Presenter do
  it "shows the sender's display name" do
    newsletter = build_stubbed(:newsletter, sender_name: "Ruby Weekly")

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.sender).to eq("Ruby Weekly")
  end

  # A row headed by a bare em dash reads as a rendering fault.
  it "names an unknown sender when the newsletter carries neither" do
    newsletter = build_stubbed(:newsletter, sender_name: "", sender_email: "")

    expect(Newsletter::Presenter.new(newsletter).sender).to eq("Unknown sender")
  end

  it "falls back to the address when the sender has no display name" do
    newsletter = build_stubbed(
      :newsletter,
      sender_name: "",
      sender_email: "peter@rubyweekly.com"
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.sender).to eq("peter@rubyweekly.com")
  end

  it "shows the time of day for a newsletter that arrived today" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-06 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("09:02")
    end
  end

  it "shows the time of day for a newsletter that arrived yesterday" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-05 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("09:02")
    end
  end

  it "shows the weekday for an older newsletter from this week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-03 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("Mon")
    end
  end

  it "shows the date for a newsletter older than a week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-07-28 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("28 Jul")
    end
  end

  it "shows the date for a newsletter older than the feed's window" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-06-01 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("1 Jun")
    end
  end

  it "says imageless mail carried no image" do
    presenter = Newsletter::Presenter.new(build_stubbed(:newsletter))

    expect(presenter.no_image).to eq("No image in email")
  end
end
