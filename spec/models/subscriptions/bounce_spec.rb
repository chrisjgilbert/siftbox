require "rails_helper"

RSpec.describe Subscriptions::Bounce do
  def refuse(source)
    ActionMailbox::InboundEmail.create_and_extract_message_id!(source, status: :bounced)
  end

  it "reads the sender's name back out of the stored source" do
    bounce = Subscriptions::Bounce.new(
      refuse("From: Ghost <no-reply@ghost.io>\nSubject: Confirm\n\nhello")
    )

    expect(bounce.sender).to eq("Ghost")
  end

  it "falls back to the address when the sender gave no name" do
    bounce = Subscriptions::Bounce.new(
      refuse("From: no-reply@ghost.io\nSubject: Confirm\n\nhello")
    )

    expect(bounce.sender).to eq("no-reply@ghost.io")
  end

  # Refused mail is the least trustworthy in the app: the From on spam is
  # forged and is often not an address list at all. A pen section that raises
  # on one malformed header is worse than the silent drop it exists to end.
  it "names a sender whose From is not an address" do
    bounce = Subscriptions::Bounce.new(
      refuse("From: Ruby Weekly\nSubject: Confirm\n\nhello")
    )

    expect(bounce.sender).to eq("Ruby Weekly")
  end

  it "names mail with no From header at all" do
    bounce = Subscriptions::Bounce.new(refuse("Subject: Confirm\n\nhello"))

    expect(bounce.sender).to eq("Unknown sender")
  end

  it "reads the subject back out of the stored source" do
    bounce = Subscriptions::Bounce.new(
      refuse("From: Ghost <no-reply@ghost.io>\nSubject: Please confirm\n\nhello")
    )

    expect(bounce.subject).to eq("Please confirm")
  end

  # When the gate refused it, not the Date the sender claimed. The Date on
  # refused mail is as forged as the rest of it.
  it "says how long ago the gate refused it" do
    inbound_email = refuse("From: Ghost <no-reply@ghost.io>\nSubject: Confirm\n\nhi")
    inbound_email.update!(created_at: 2.days.ago)

    expect(Subscriptions::Bounce.new(inbound_email).freshness).to eq("2 days ago")
  end

  it "draws itself as an unlinked pen row" do
    bounce = Subscriptions::Bounce.new(
      refuse("From: Ghost <no-reply@ghost.io>\nSubject: Confirm\n\nhello")
    )

    expect(bounce.to_partial_path).to eq("subscriptions/bounce")
  end

  it "collects the mail the gate refused, newest first" do
    older = refuse("From: a@ghost.io\nSubject: First\n\nhello")
    older.update!(created_at: 3.days.ago)
    refuse("From: b@ghost.io\nSubject: Second\n\nhello")

    expect(Subscriptions::Bounce.recent.map(&:subject)).to eq([ "Second", "First" ])
  end

  it "leaves out mail refused longer ago than Action Mailbox keeps it" do
    inbound_email = refuse("From: a@ghost.io\nSubject: First\n\nhello")
    inbound_email.update!(created_at: ActionMailbox.incinerate_after.ago - 1.day)

    expect(Subscriptions::Bounce.recent).to be_empty
  end

  # Read off Action Mailbox's own retention rather than written down, so the
  # empty line cannot promise thirty days after someone shortens incineration.
  it "counts the retention in days" do
    expect(Subscriptions::Bounce.retention_days).to eq(30)
  end
end
