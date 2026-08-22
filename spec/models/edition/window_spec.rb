require "rails_helper"

RSpec.describe Edition::Window do
  # 07:00 in the reader's zone, which is when the schedule composes and so the
  # only clock reading a real window ever gets.
  def morning
    Time.zone.local(2026, 8, 15, 7)
  end

  def yesterday_morning
    morning - 1.day
  end

  # The edition the watermark is read off. Only its window_ended_at matters
  # here; the number and the date are the factory's business.
  def published_through(ended_at)
    create(:edition, window_started_at: ended_at - 1.day, window_ended_at: ended_at)
  end

  def window
    Edition::Window.new(morning)
  end

  def confirmation(received_at:, released_at: nil)
    create(:newsletter, received_at: received_at, held_at: received_at,
      released_at: released_at)
  end

  it "ends at the moment composition started" do
    expect(window.ended_at).to eq(morning)
  end

  it "starts where the last edition's window ended" do
    published_through(yesterday_morning)

    expect(window.started_at).to eq(yesterday_morning)
  end

  # maximum(:window_ended_at), not Edition.latest.window_ended_at. An edition
  # backfilled for an earlier day sorts to the top of nothing, and taking its
  # cutoff as the watermark would re-compose every newsletter since.
  it "starts at the newest window close when editions were composed out of order" do
    published_through(yesterday_morning)
    create(:edition, published_on: Date.new(2026, 7, 1),
      window_started_at: morning - 40.days, window_ended_at: morning - 39.days)

    expect(window.started_at).to eq(yesterday_morning)
  end

  it "covers a newsletter that arrived after the last edition's cutoff" do
    published_through(yesterday_morning)
    arrival = create(:newsletter, received_at: yesterday_morning + 2.hours)

    expect(window.newsletters).to eq([ arrival ])
  end

  it "leaves out a newsletter the last edition already covered" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: yesterday_morning - 2.hours)

    expect(window.newsletters).to be_empty
  end

  # The whole reason the window has two clauses. A confirmation sits in the pen
  # for days, so by the time the reader releases it its received_at is well
  # behind the watermark — and a received_at-only window would drop it from
  # this edition and from every edition there will ever be.
  it "covers a newsletter released after the cutoff though it arrived before it" do
    published_through(yesterday_morning)
    late = confirmation(received_at: yesterday_morning - 3.days,
      released_at: yesterday_morning + 1.hour)

    expect(window.newsletters).to eq([ late ])
  end

  it "leaves out a newsletter still held in the confirmation pen" do
    published_through(yesterday_morning)
    confirmation(received_at: yesterday_morning + 2.hours)

    expect(window.newsletters).to be_empty
  end

  it "leaves out a newsletter dismissed out of the pen" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: yesterday_morning + 2.hours,
      held_at: yesterday_morning + 2.hours, dismissed_at: morning - 1.hour)

    expect(window.newsletters).to be_empty
  end

  # Released into the previous edition's window, cited there, and done with.
  it "leaves out a newsletter released before the last edition's cutoff" do
    published_through(yesterday_morning)
    confirmation(received_at: yesterday_morning - 3.days,
      released_at: yesterday_morning - 1.hour)

    expect(window.newsletters).to be_empty
  end

  # Composition takes a minute or two and the query runs inside it. Without a
  # top to the window, mail landing in that minute would be composed into this
  # edition and still sit above the watermark for the next one.
  it "leaves out a newsletter that arrived after composition started" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: morning + 1.minute)

    expect(window.newsletters).to be_empty
  end

  it "leaves out a newsletter released after composition started" do
    published_through(yesterday_morning)
    confirmation(received_at: yesterday_morning - 3.days, released_at: morning + 1.minute)

    expect(window.newsletters).to be_empty
  end

  # The previous edition's window is closed at the top, so the instant it ended
  # belongs to that edition. Inclusive at both ends would put one newsletter
  # into two editions.
  it "leaves out a newsletter received at the instant the last window closed" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: yesterday_morning)

    expect(window.newsletters).to be_empty
  end

  it "covers a newsletter received at the instant composition started" do
    published_through(yesterday_morning)
    arrival = create(:newsletter, received_at: morning)

    expect(window.newsletters).to eq([ arrival ])
  end

  # Released mail that also arrived inside the window satisfies both clauses,
  # and a newsletter handed to the model twice is one it can cite twice.
  it "covers a newsletter matching both clauses once" do
    published_through(yesterday_morning)
    both = confirmation(received_at: yesterday_morning + 1.hour,
      released_at: yesterday_morning + 2.hours)

    expect(window.newsletters).to eq([ both ])
  end

  it "reads oldest first" do
    published_through(yesterday_morning)
    later = create(:newsletter, received_at: yesterday_morning + 4.hours)
    earlier = create(:newsletter, received_at: yesterday_morning + 2.hours)

    expect(window.newsletters).to eq([ earlier, later ])
  end

  # Edition::Prompt reads body_html. A column list here — FEED_COLUMNS omits
  # it — would send the model an edition's worth of subject lines and nothing
  # to write from.
  it "loads the bodies the editor has to read" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: morning - 1.hour, body_html: "<p>The S-1 landed.</p>")

    expect(window.newsletters.first.body_html).to eq("<p>The S-1 landed.</p>")
  end

  it "is empty when nothing arrived since the last edition" do
    published_through(yesterday_morning)

    expect(window).to be_empty
  end

  it "is not empty when a newsletter arrived since the last edition" do
    published_through(yesterday_morning)
    create(:newsletter, received_at: morning - 1.hour)

    expect(window).not_to be_empty
  end

  # No watermark to start from, and no floor either: the archive holds weeks of
  # mail from before editions existed, and one prompt carrying all of it is an
  # edition nobody asked for at a price nobody budgeted.
  it "reaches a day back when there is no edition to follow" do
    expect(window.started_at).to eq(morning - Edition::Window::FIRST_WINDOW)
  end

  it "covers the day's mail when there is no edition to follow" do
    arrival = create(:newsletter, received_at: morning - 2.hours)

    expect(window.newsletters).to eq([ arrival ])
  end

  it "leaves out mail older than a day when there is no edition to follow" do
    create(:newsletter, received_at: morning - 2.days)

    expect(window.newsletters).to be_empty
  end

  it "numbers the first edition No. 1" do
    expect(window.edition.number).to eq(1)
  end

  it "numbers an edition above every number published so far" do
    create(:edition, number: 9, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 3, published_on: Date.new(2026, 8, 12))

    expect(window.edition.number).to eq(10)
  end

  it "records the window the edition covers" do
    published_through(yesterday_morning)

    expect(window.edition.window_started_at).to eq(yesterday_morning)
    expect(window.edition.window_ended_at).to eq(morning)
  end

  # The day the reader picks it up, the way a morning paper is dated: the
  # window behind it is mostly yesterday's mail.
  it "dates the edition by the morning it was composed on" do
    expect(window.edition.published_on).to eq(Date.new(2026, 8, 15))
  end

  it "publishes the edition at the moment composition started" do
    expect(window.edition.published_at).to eq(morning)
  end

  it "leaves the edition unsaved for the editor to fill in" do
    expect(window.edition).not_to be_persisted
  end

  it "covers a post this app first saw after the last edition's cutoff" do
    published_through(yesterday_morning)
    post = create(:blog_post, received_at: yesterday_morning + 2.hours)

    expect(window.posts).to eq([ post ])
  end

  it "leaves out a post the last edition already covered" do
    published_through(yesterday_morning)
    create(:blog_post, received_at: yesterday_morning - 2.hours)

    expect(window.posts).to be_empty
  end

  # received_at rather than published_at, and the difference is the whole
  # reason blog_posts carries both. A feed hands over a back catalogue, so a
  # post can be published years before this app ever reads it — dating the
  # window on the publisher's claim would put an archive into one edition.
  it "covers a post published long ago but first seen inside the window" do
    published_through(yesterday_morning)
    post = create(:blog_post, published_at: 3.years.before(morning),
      received_at: yesterday_morning + 2.hours)

    expect(window.posts).to eq([ post ])
  end

  it "leaves out a post that arrived after composition started" do
    published_through(yesterday_morning)
    create(:blog_post, received_at: morning + 1.minute)

    expect(window.posts).to be_empty
  end

  it "reads posts oldest first" do
    published_through(yesterday_morning)
    second = create(:blog_post, received_at: yesterday_morning + 3.hours)
    first = create(:blog_post, received_at: yesterday_morning + 2.hours)

    expect(window.posts).to eq([ first, second ])
  end

  # Whole rows for the same reason the newsletters are: Edition::Prompt reads
  # body_html, and the feed's column list leaves it out.
  it "reads a post's whole row" do
    published_through(yesterday_morning)
    create(:blog_post, body_html: "<p>Hi</p>", received_at: yesterday_morning + 2.hours)

    expect(window.posts.sole.body_html).to eq("<p>Hi</p>")
  end

  it "is not empty when only a post arrived" do
    published_through(yesterday_morning)
    create(:blog_post, received_at: yesterday_morning + 2.hours)

    expect(window).not_to be_empty
  end

  it "hands the editor both kinds of source" do
    published_through(yesterday_morning)
    newsletter = create(:newsletter, received_at: yesterday_morning + 1.hour)
    post = create(:blog_post, received_at: yesterday_morning + 2.hours)

    sources = window.sources

    expect(sources.newsletters).to eq([ newsletter ])
    expect(sources.posts).to eq([ post ])
  end
end
