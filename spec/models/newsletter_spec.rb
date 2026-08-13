require "rails_helper"

RSpec.describe Newsletter do
  it "orders newest first" do
    older = create(:newsletter, received_at: 2.days.ago)
    newer = create(:newsletter, received_at: 1.hour.ago)

    expect(Newsletter.newest_first).to eq([ newer, older ])
  end

  it "counts only newsletters that have not been read as unread" do
    unread = create(:newsletter, read_at: nil)
    create(:newsletter, read_at: 1.hour.ago)

    expect(Newsletter.unread).to eq([ unread ])
  end

  it "is read once read_at is set" do
    newsletter = build_stubbed(:newsletter, read_at: 1.hour.ago)

    expect(newsletter).to be_read
  end

  it "is not read while read_at is blank" do
    newsletter = build_stubbed(:newsletter, read_at: nil)

    expect(newsletter).not_to be_read
  end

  it "records the time when marked read" do
    newsletter = create(:newsletter, read_at: nil)

    newsletter.mark_read

    expect(newsletter.reload.read_at).to be_present
  end

  it "keeps the original time when marked read a second time" do
    first_read = 3.days.ago
    newsletter = create(:newsletter, read_at: first_read)

    newsletter.mark_read

    expect(newsletter.reload.read_at).to be_within(1.second).of(first_read)
  end

  it "clears the time when marked unread" do
    newsletter = create(:newsletter, read_at: 1.hour.ago)

    newsletter.mark_unread

    expect(newsletter.reload.read_at).to be_nil
  end

  it "takes the sender domain from the sender address" do
    newsletter = build_stubbed(:newsletter, sender_email: "peter@rubyweekly.com")

    expect(newsletter.sender_domain).to eq("rubyweekly.com")
  end

  it "has no sender domain when the sender address is blank" do
    newsletter = build_stubbed(:newsletter, sender_email: "")

    expect(newsletter.sender_domain).to eq("")
  end

  it "finds the newsletter received just after it" do
    newsletter = create(:newsletter, received_at: 2.days.ago)
    newer = create(:newsletter, received_at: 1.day.ago)
    create(:newsletter, received_at: 3.days.ago)

    expect(newsletter.newer).to eq(newer)
  end

  it "finds the newsletter received just before it" do
    newsletter = create(:newsletter, received_at: 2.days.ago)
    older = create(:newsletter, received_at: 3.days.ago)
    create(:newsletter, received_at: 1.day.ago)

    expect(newsletter.older).to eq(older)
  end

  it "reaches a newsletter that shares its received time" do
    shared = Time.zone.parse("2026-08-05 09:02:00")
    first = create(:newsletter, received_at: shared)
    second = create(:newsletter, received_at: shared)

    expect(first.newer).to eq(second)
  end

  it "reaches back to a newsletter that shares its received time" do
    shared = Time.zone.parse("2026-08-05 09:02:00")
    first = create(:newsletter, received_at: shared)
    second = create(:newsletter, received_at: shared)

    expect(second.older).to eq(first)
  end

  it "orders newsletters sharing a received time consistently" do
    shared = Time.zone.parse("2026-08-05 09:02:00")
    first = create(:newsletter, received_at: shared)
    second = create(:newsletter, received_at: shared)

    expect(Newsletter.newest_first).to eq([ second, first ])
  end

  it "has no newer newsletter when it is the most recent" do
    create(:newsletter, received_at: 3.days.ago)
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(newsletter.newer).to be_nil
  end

  it "requires a received time" do
    expect(build(:newsletter)).to validate_presence_of(:received_at)
  end

  it "captures the first body image as the lead image" do
    newsletter = create(:newsletter, body_html: %(<img src="https://cdn.example/hero.png">))

    newsletter.capture_lead_image

    expect(newsletter.reload.lead_image_url).to eq("https://cdn.example/hero.png")
  end

  it "captures no lead image for a newsletter whose body has none" do
    newsletter = create(:newsletter, body_html: "<p>Morning</p>", lead_image_url: "")

    newsletter.capture_lead_image

    expect(newsletter.reload.lead_image_url).to eq("")
  end

  it "has a lead image once one is captured" do
    newsletter = build_stubbed(:newsletter, lead_image_url: "https://cdn.example/hero.png")

    expect(newsletter).to be_lead_image
  end

  it "has no lead image while the column is blank" do
    newsletter = build_stubbed(:newsletter, lead_image_url: "")

    expect(newsletter).not_to be_lead_image
  end

  # What the backfill walks. Newsletters stored before the column existed all
  # sit at "", and so do newsletters that genuinely carry no image.
  it "finds the newsletters with no lead image captured" do
    without = create(:newsletter, lead_image_url: "")
    create(:newsletter, lead_image_url: "https://cdn.example/hero.png")

    expect(Newsletter.without_lead_image).to eq([ without ])
  end

  # SQLite stops reading a string literal at a NUL, so one stray byte fails
  # the INSERT. Held on the record rather than in the mail reader, because
  # Newsletter::InlineImages and Newsletter::RemoteImages both rewrite
  # body_html later without going near it.
  it "strips a null byte from a body rewritten after ingest" do
    newsletter = create(:newsletter)

    newsletter.update!(body_html: "<p>rewritten#{0.chr} by a job</p>")

    expect(newsletter.reload.body_html).to eq("<p>rewritten by a job</p>")
  end

  it "strips a null byte from a header the mail reader never guarded" do
    newsletter = create(:newsletter, subject: "Issue#{0.chr} 742")

    expect(newsletter.reload.subject).to eq("Issue 742")
  end

  it "is held while held_at is set and nothing has resolved it" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago)

    expect(newsletter).to be_held
  end

  it "is not held while held_at is blank" do
    newsletter = build_stubbed(:newsletter, held_at: nil)

    expect(newsletter).not_to be_held
  end

  it "is no longer held once dismissed" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, dismissed_at: 1.minute.ago)

    expect(newsletter).not_to be_held
  end

  it "is no longer held once released" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, released_at: 1.minute.ago)

    expect(newsletter).not_to be_held
  end

  it "is dismissed once dismissed_at is set" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, dismissed_at: 1.minute.ago)

    expect(newsletter).to be_dismissed
  end

  it "is not dismissed while dismissed_at is blank" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, dismissed_at: nil)

    expect(newsletter).not_to be_dismissed
  end

  it "is released once released_at is set" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, released_at: 1.minute.ago)

    expect(newsletter).to be_released
  end

  it "is not released while released_at is blank" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, released_at: nil)

    expect(newsletter).not_to be_released
  end

  it "is resolved once dismissed" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, dismissed_at: 1.minute.ago)

    expect(newsletter).to be_resolved
  end

  it "is resolved once released" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago, released_at: 1.minute.ago)

    expect(newsletter).to be_resolved
  end

  it "is not resolved while it is still waiting in the pen" do
    newsletter = build_stubbed(:newsletter, held_at: 1.hour.ago)

    expect(newsletter).not_to be_resolved
  end

  it "records the time when held as a suspected confirmation" do
    newsletter = create(:newsletter, held_at: nil)

    newsletter.hold

    expect(newsletter.reload).to be_held
  end

  it "keeps the original hold time when held a second time" do
    first_hold = 3.days.ago
    newsletter = create(:newsletter, held_at: first_hold)

    newsletter.hold

    expect(newsletter.reload.held_at).to be_within(1.second).of(first_hold)
  end

  # The PRD's backtests want the heuristic run over stored rows. A backfill
  # that re-held mail the reader had already released would undo the
  # correction and drop the newsletter back out of the archive.
  it "leaves a released newsletter released when held again" do
    newsletter = create(:newsletter, held_at: 2.days.ago, released_at: 1.day.ago)

    newsletter.hold

    expect(newsletter.reload).to be_released
  end

  it "records the time when held mail is dismissed" do
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    newsletter.dismiss

    expect(newsletter.reload).to be_dismissed
  end

  it "refuses to dismiss mail that was never held" do
    newsletter = create(:newsletter, held_at: nil)

    expect { newsletter.dismiss }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "refuses to dismiss mail already released" do
    newsletter = create(:newsletter, held_at: 2.days.ago, released_at: 1.day.ago)

    expect { newsletter.dismiss }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "records the time when held mail is released as content" do
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    newsletter.release

    expect(newsletter.reload).to be_released
  end

  it "refuses to release mail that was never held" do
    newsletter = create(:newsletter, held_at: nil)

    expect { newsletter.release }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "refuses to release mail already dismissed" do
    newsletter = create(:newsletter, held_at: 2.days.ago, dismissed_at: 1.day.ago)

    expect { newsletter.release }.to raise_error(ActiveRecord::RecordInvalid)
  end

  # What the Subscriptions page's first section lists and the edition page's
  # badge counts: mail in the pen right now, not mail that was ever in it.
  it "finds the held mail still awaiting action" do
    waiting = create(:newsletter, held_at: 1.hour.ago)
    create(:newsletter, held_at: 2.days.ago, dismissed_at: 1.day.ago)
    create(:newsletter, held_at: 2.days.ago, released_at: 1.day.ago)
    create(:newsletter, held_at: nil)

    expect(Newsletter.held).to eq([ waiting ])
  end

  it "finds the held mail that has been dismissed" do
    dismissed = create(:newsletter, held_at: 2.days.ago, dismissed_at: 1.day.ago)
    create(:newsletter, held_at: 1.hour.ago)

    expect(Newsletter.dismissed).to eq([ dismissed ])
  end

  it "finds the held mail that has been released" do
    released = create(:newsletter, held_at: 2.days.ago, released_at: 1.day.ago)
    create(:newsletter, held_at: 1.hour.ago)

    expect(Newsletter.released).to eq([ released ])
  end

  it "counts a newsletter that was never held as content" do
    newsletter = create(:newsletter, held_at: nil)

    expect(Newsletter.content).to eq([ newsletter ])
  end

  it "keeps mail waiting in the pen out of the content" do
    create(:newsletter, held_at: 1.hour.ago)

    expect(Newsletter.content).to be_empty
  end

  it "keeps dismissed mail out of the content" do
    create(:newsletter, held_at: 2.days.ago, dismissed_at: 1.day.ago)

    expect(Newsletter.content).to be_empty
  end

  it "returns released mail to the content" do
    newsletter = create(:newsletter, held_at: 2.days.ago, released_at: 1.day.ago)

    expect(Newsletter.content).to eq([ newsletter ])
  end

  # The archive narrows to a week before it asks for content. An `or` that
  # dropped the received_at condition off one of its two branches would widen
  # the window back out silently.
  it "narrows to content within a window the caller has already applied" do
    inside = create(:newsletter, received_at: 1.hour.ago)
    create(:newsletter, received_at: 3.weeks.ago)

    expect(Newsletter.where(received_at: 1.week.ago..).content).to eq([ inside ])
  end
end
