require "rails_helper"

RSpec.describe Newsletter::Age do
  it "says how long ago mail arrived" do
    age = Newsletter::Age.new(4.minutes.ago)

    expect(age.in_words).to eq("4 minutes ago")
  end

  it "says the same of mail that arrived days back" do
    age = Newsletter::Age.new(3.days.ago)

    expect(age.in_words).to eq("3 days ago")
  end

  # A confirmation the reader opens within the minute is the common case, and
  # "0 minutes ago" would read as a rendering fault.
  it "says less than a minute of mail that has only just landed" do
    age = Newsletter::Age.new(2.seconds.ago)

    expect(age.in_words).to eq("less than a minute ago")
  end

  # The clock face and the bucket answered by one object, which is the whole
  # claim this class makes: a row cannot be formatted by one rule and filed
  # under a heading decided by another.
  it "prints the time of day for something that arrived today" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      age = Newsletter::Age.new(Time.zone.parse("2026-08-06 09:02"))

      expect(age.timestamp).to eq("09:02")
    end
  end

  it "prints the day for something earlier in the week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      age = Newsletter::Age.new(Time.zone.parse("2026-08-03 09:02"))

      expect(age.timestamp).to eq("Mon")
    end
  end

  it "prints the date for something older than the week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      age = Newsletter::Age.new(Time.zone.parse("2026-06-11 09:02"))

      expect(age.timestamp).to eq("11 Jun")
    end
  end

  it "prints the time of day for something dated in the future" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      age = Newsletter::Age.new(Time.zone.parse("2026-08-07 09:02"))

      expect(age.timestamp).to eq("09:02")
    end
  end
end
