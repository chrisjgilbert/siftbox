require "rails_helper"

RSpec.describe Edition::Gap::Presenter do
  def gap_on(covered_on)
    Edition::Gap.new(covered_on: covered_on, reason: Edition::Gap::FAILED)
  end

  # Stands where an edition's number does. The archive's rows are read down
  # that column, so a morning with no edition has to say so there rather than
  # leave it blank and let the date carry an explanation it cannot give.
  it "says there is no edition where the number goes" do
    presenter = Edition::Gap::Presenter.new(gap_on(Date.new(2026, 8, 15)))

    expect(presenter.number).to eq("No edition")
  end

  it "dates the morning it stood in for" do
    presenter = Edition::Gap::Presenter.new(gap_on(Date.new(2026, 8, 15)))

    expect(presenter.date).to eq("Saturday 15 August")
  end

  # What the archive sorts by, answered by both presenters so one list can
  # hold published mornings and failed ones.
  it "files under the day it covered" do
    presenter = Edition::Gap::Presenter.new(gap_on(Date.new(2026, 8, 15)))

    expect(presenter.covered_on).to eq(Date.new(2026, 8, 15))
  end

  # There is no edition to open, and a row that looked like a link and led to
  # a 404 would be worse than a row that plainly is not one.
  it "draws through a template of its own" do
    presenter = Edition::Gap::Presenter.new(gap_on(Date.new(2026, 8, 15)))

    expect(presenter.to_partial_path).to eq("editions/gap_row")
  end
end
