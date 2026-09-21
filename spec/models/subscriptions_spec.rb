require "rails_helper"

RSpec.describe Subscriptions do
  def headings
    Subscriptions.new.sections.map(&:heading)
  end

  def section(name)
    Subscriptions.new.sections.detect { |drawn| drawn.name == name }
  end

  it "draws the three sections in the order the page reads them" do
    expect(headings).to eq([ "Awaiting confirmation", "New senders", "Recently bounced" ])
  end

  # Against Edition::Presenter, which drops a section the edition has nothing
  # for. A pen section that vanishes when empty reads as a broken page rather
  # than a calm one, and the two sections a reader checks after subscribing
  # are the ones most often empty.
  it "draws a section with nothing in it" do
    expect(section("bounced")).not_to be_any
  end

  it "lists mail waiting in the pen under awaiting confirmation" do
    create(:newsletter, subject: "Confirm your subscription", held_at: 1.hour.ago)

    expect(section("awaiting").rows.map(&:subject)).to eq([ "Confirm your subscription" ])
  end

  it "leaves resolved mail out of awaiting confirmation" do
    create(:newsletter, held_at: 2.days.ago, dismissed_at: 1.day.ago)

    expect(section("awaiting")).not_to be_any
  end

  it "lists the first mail from a new address under new senders" do
    create(:newsletter, sender_email: "hello@thediff.co", subject: "Issue 1",
      received_at: 2.days.ago)

    expect(section("new_senders").rows.map(&:subject)).to eq([ "Issue 1" ])
  end

  # "The last couple of weeks", per the PRD. A sender who first wrote in April
  # is not news, and an unbounded list would be every address there has ever
  # been.
  it "leaves an address that first wrote before the window out of new senders" do
    create(:newsletter, sender_email: "hello@thediff.co", received_at: 5.weeks.ago)

    expect(section("new_senders")).not_to be_any
  end

  it "lists a bounced inbound email under recently bounced" do
    ActionMailbox::InboundEmail.create_and_extract_message_id!(
      "From: Ghost <no-reply@ghost.io>\nSubject: Confirm\n\nhello", status: :bounced
    )

    expect(section("bounced").rows.map(&:subject)).to eq([ "Confirm" ])
  end

  it "leaves a delivered inbound email out of recently bounced" do
    ActionMailbox::InboundEmail.create_and_extract_message_id!(
      "From: Ghost <no-reply@ghost.io>\nSubject: Confirm\n\nhello", status: :delivered
    )

    expect(section("bounced")).not_to be_any
  end

  it "lists the roster newest first, so a blog just added is at the top" do
    create(:blog, feed_url: "https://first.dev/feed", title: "First")
    create(:blog, feed_url: "https://second.dev/feed", title: "Second")

    expect(Subscriptions.new.sources.map(&:name)).to eq([ "Second", "First" ])
  end

  # The grouped count answers nothing for a blog with no posts, and the row
  # has to read that as none rather than as one.
  it "counts a blog with nothing stored yet as none" do
    create(:blog, title: "Query Plan Weekly")

    expect(Subscriptions.new.sources.map(&:count)).to eq([ "0 posts" ])
  end

  it "counts the posts each blog has stored" do
    blog = create(:blog, title: "Query Plan Weekly")
    create_list(:blog_post, 2, blog: blog)

    expect(Subscriptions.new.sources.map(&:count)).to eq([ "2 posts" ])
  end

  # One roster holding both kinds of source, because a reader deciding what
  # reaches them is answering one question. The blogs come first: the section
  # is where a blog is added, and a muted sender is the tail of decisions
  # that have nowhere else to live.
  it "lists muted senders under the blogs" do
    create(:blog, title: "Query Plan Weekly")
    create(:newsletter_sender, name: "Ruby Weekly", silenced_at: 1.day.ago)

    expect(Subscriptions.new.sources.map(&:name))
      .to eq([ "Query Plan Weekly", "Ruby Weekly" ])
  end

  # A muted blog is still a blog: it keeps its place among them with its poll
  # state showing, rather than moving to the muted tail. The tail is for
  # senders, who have no other reason to be on the roster at all.
  it "keeps a muted blog among the blogs" do
    create(:blog, title: "Query Plan Weekly", silenced_at: 1.day.ago)
    create(:newsletter_sender, name: "Ruby Weekly", silenced_at: 1.day.ago)

    expect(Subscriptions.new.sources.map(&:name))
      .to eq([ "Query Plan Weekly", "Ruby Weekly" ])
  end

  # A sender the reader has not muted has no decision recorded about them, so
  # there is nothing to list. The roster holds decisions, not addresses.
  it "leaves a sender nobody has muted off the roster" do
    create(:newsletter_sender, name: "Ruby Weekly", silenced_at: nil)

    expect(Subscriptions.new.sources).to be_empty
  end

  it "lists the muted senders newest first" do
    create(:newsletter_sender, name: "Earlier", silenced_at: 3.days.ago)
    create(:newsletter_sender, name: "Later", silenced_at: 1.day.ago)

    expect(Subscriptions.new.sources.map(&:name)).to eq([ "Later", "Earlier" ])
  end

  # Each row picks the template that draws it, so the view never asks which
  # kind it is holding — the way the editions archive holds editions and gaps.
  it "draws a blog and a muted sender through templates of their own" do
    create(:blog, title: "Query Plan Weekly")
    create(:newsletter_sender, name: "Ruby Weekly", silenced_at: 1.day.ago)

    expect(Subscriptions.new.sources.map(&:to_partial_path))
      .to eq([ "blogs/row", "newsletter_senders/row" ])
  end

  # A fresh one on an ordinary visit; the refused one when BlogsController
  # re-renders this page, so the reader sees what they typed and why.
  it "hands the form a blog to fill in" do
    expect(Subscriptions.new.blog).to be_a_new(Blog)
  end

  it "hands the form the blog it was given" do
    refused = Blog.new(feed_url: "https://news.ycombinator.com/rss")

    expect(Subscriptions.new(blog: refused).blog).to eq(refused)
  end
end
