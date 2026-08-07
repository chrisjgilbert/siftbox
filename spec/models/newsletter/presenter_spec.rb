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

  it "has no sender domain when the address is missing" do
    newsletter = build_stubbed(:newsletter, sender_name: "", sender_email: "")

    expect(Newsletter::Presenter.new(newsletter).sender_domain).to be_nil
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

  it "spells out the received line for the reader" do
    newsletter = build_stubbed(
      :newsletter,
      received_at: Time.zone.parse("2026-08-05 09:02")
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.received_line).to eq("Received 5 August 2026 at 09:02")
  end

  it "titles a neighbour with its sender and subject" do
    newsletter = build_stubbed(
      :newsletter,
      sender_name: "Ruby Weekly",
      subject: "Issue 742"
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.title).to eq("Ruby Weekly — Issue 742")
  end

  # `title` is the presenter's own, so this fails if the neighbour comes back
  # unwrapped — which `subject` alone could not tell apart.
  it "wraps the newer neighbour in a presenter" do
    create(:newsletter, received_at: 2.days.ago)
    create(:newsletter, received_at: 1.day.ago, sender_name: "Ruby Weekly",
      subject: "Later one")
    presenter = Newsletter::Presenter.new(Newsletter.order(:received_at).first)

    expect(presenter.newer.title).to eq("Ruby Weekly — Later one")
  end

  it "wraps the older neighbour in a presenter" do
    create(:newsletter, received_at: 2.days.ago, sender_name: "Ruby Weekly",
      subject: "Earlier one")
    create(:newsletter, received_at: 1.day.ago)
    presenter = Newsletter::Presenter.new(Newsletter.order(:received_at).last)

    expect(presenter.older.title).to eq("Ruby Weekly — Earlier one")
  end

  it "has no older neighbour when it is the oldest" do
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(Newsletter::Presenter.new(newsletter).older).to be_nil
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

  it "has no newer neighbour when it is the most recent" do
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(Newsletter::Presenter.new(newsletter).newer).to be_nil
  end
end
