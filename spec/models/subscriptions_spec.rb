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
end
