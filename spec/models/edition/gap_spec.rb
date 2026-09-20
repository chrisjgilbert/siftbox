require "rails_helper"

RSpec.describe Edition::Gap do
  def window(ended_at)
    Edition::Window.new(ended_at)
  end

  it "records a window that held nothing" do
    gap = Edition::Gap.empty(window(Time.current))

    expect(gap).to be_empty_window
  end

  it "records a window composition could not answer for" do
    gap = Edition::Gap.failed(window(Time.current), "the model declined")

    expect(gap).to be_failed
  end

  it "keeps what went wrong beside the failure" do
    gap = Edition::Gap.failed(window(Time.current), "the model declined")

    expect(gap.detail).to eq("the model declined")
  end

  it "covers the window it was recorded for" do
    morning = Time.zone.local(2026, 8, 15, 7)
    create(:edition, window_started_at: morning - 2.days, window_ended_at: morning - 1.day)

    gap = Edition::Gap.empty(window(morning))

    expect(gap.window_started_at).to eq(morning - 1.day)
    expect(gap.window_ended_at).to eq(morning)
  end

  # Dated the way an edition is, so the archive can file the two together.
  it "is dated by the morning it stood in for" do
    morning = Time.zone.local(2026, 8, 15, 7)

    expect(Edition::Gap.empty(window(morning)).covered_on).to eq(Date.new(2026, 8, 15))
  end

  # One morning has one outcome, and a second run of the same morning is a
  # double-fired schedule rather than a new fact. It must not raise: the
  # failure handlers are what call this, so an exception here escapes the
  # handler and takes the job down without recording anything.
  it "keeps one gap for a morning recorded twice" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.empty(window(morning))

    Edition::Gap.empty(window(morning))

    expect(Edition::Gap.count).to eq(1)
  end

  # A morning that found nothing and was then tried again and failed has
  # something to explain after all, so the failure takes over the row.
  it "upgrades an empty morning to a failure" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.empty(window(morning))

    Edition::Gap.failed(window(morning), "the model declined")

    expect(Edition::Gap.sole).to be_failed
  end

  # The gap closed the window, so a re-run the same morning finds nothing
  # above the watermark and reports an empty window. The explanation has to
  # survive that: what went wrong is still what went wrong.
  it "keeps a failed morning failed when a later run finds nothing" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.failed(window(morning), "the model declined")

    Edition::Gap.empty(window(morning))

    expect(Edition::Gap.sole).to be_failed
  end

  it "keeps the first explanation when a failed morning fails again" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.failed(window(morning), "the model declined")

    Edition::Gap.failed(window(morning), "something else")

    expect(Edition::Gap.sole.detail).to eq("the model declined")
  end

  # Only the failures. An empty morning is a morning nothing arrived on, which
  # the reader can see for themselves in the archive; a failed one is the app
  # owing them an explanation.
  it "lists the failures for the archive" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.empty(window(morning))
    broken = Edition::Gap.failed(window(morning + 1.day), "the model declined")

    expect(Edition::Gap.failed_first).to eq([ broken ])
  end

  it "takes the watermark from the newest window it has covered" do
    morning = Time.zone.local(2026, 8, 15, 7)
    Edition::Gap.empty(window(morning))
    Edition::Gap.empty(window(morning + 1.day))

    expect(Edition::Gap.watermark).to eq(morning + 1.day)
  end

  it "has no watermark before anything has been covered" do
    expect(Edition::Gap.watermark).to be_nil
  end
end
