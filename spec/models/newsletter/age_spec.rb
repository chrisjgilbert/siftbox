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
end
