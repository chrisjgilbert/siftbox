require "rails_helper"

RSpec.describe Newsletter::Sender do
  it "requires an address" do
    expect(build(:newsletter_sender)).to validate_presence_of(:sender_email)
  end

  # The column, not the validation, and the difference matters to the window.
  # Newsletter.unsilenced asks whether a muted row matches the mail's address;
  # written as a NOT IN, one row with no address would make that never true
  # and empty the window — an edition about nothing. It is written as a NOT
  # EXISTS, which has no such failure mode, and this constraint is why the
  # state cannot arise in the first place.
  it "refuses a row with no address even when validations are skipped" do
    expect { Newsletter::Sender.insert({ sender_email: nil,
      created_at: Time.current, updated_at: Time.current }) }
      .to raise_error(ActiveRecord::NotNullViolation)
  end

  it "is not silenced when it has never been muted" do
    sender = build_stubbed(:newsletter_sender, silenced_at: nil)

    expect(sender).not_to be_silenced
  end

  it "is silenced once it has been muted" do
    sender = build_stubbed(:newsletter_sender, silenced_at: 1.day.ago)

    expect(sender).to be_silenced
  end

  it "records when it was muted" do
    sender = create(:newsletter_sender, silenced_at: nil)

    sender.silence

    expect(sender.silenced_at).to be_present
  end

  # Muting twice is the reader pressing a button they cannot see the state of,
  # not a new decision. The first time is when they decided, and the roster
  # prints that date.
  it "keeps the first muting when muted again" do
    sender = create(:newsletter_sender, silenced_at: 2.days.ago)
    stamped = sender.silenced_at

    sender.silence

    expect(sender.reload.silenced_at).to eq(stamped)
  end

  it "stops being silenced when unmuted" do
    sender = create(:newsletter_sender, silenced_at: 1.day.ago)

    sender.unsilence

    expect(sender).not_to be_silenced
  end

  it "lists the senders that are muted" do
    muted = create(:newsletter_sender, silenced_at: 1.day.ago)
    create(:newsletter_sender, silenced_at: nil)

    expect(Newsletter::Sender.silenced).to eq([ muted ])
  end

  # The roster row is made at the moment the reader mutes, because until then
  # there is nothing to record: a sender is an address on the mail it sent.
  it "takes its address from the newsletter it was muted from" do
    newsletter = create(:newsletter, sender_email: "peter@rubyweekly.com")

    sender = Newsletter::Sender.muting(newsletter)

    expect(sender.sender_email).to eq("peter@rubyweekly.com")
  end

  it "takes its name from the newsletter it was muted from" do
    newsletter = create(:newsletter, sender_name: "Ruby Weekly")

    expect(Newsletter::Sender.muting(newsletter).name).to eq("Ruby Weekly")
  end

  it "is silenced from the moment it is muted" do
    newsletter = create(:newsletter, sender_email: "peter@rubyweekly.com")

    expect(Newsletter::Sender.muting(newsletter)).to be_silenced
  end

  # A second mute of the same address finds the standing row rather than
  # failing on the unique index. The reader can reach the button from any
  # issue the sender has ever sent.
  it "keeps one row for an address muted from two issues" do
    create(:newsletter, sender_email: "peter@rubyweekly.com")
    Newsletter::Sender.muting(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    Newsletter::Sender.muting(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    expect(Newsletter::Sender.count).to eq(1)
  end

  # Senders do not write from one casing. A row stored as it was first seen
  # has to match mail that arrives shouting, or the silence is escaped by a
  # sender changing nothing but their own From header.
  it "finds a standing row whatever case the address arrives in" do
    Newsletter::Sender.muting(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    Newsletter::Sender.muting(create(:newsletter, sender_email: "Peter@RubyWeekly.com"))

    expect(Newsletter::Sender.count).to eq(1)
  end

  # Muting again after an unmute is a fresh decision, and the roster prints
  # the date of the one that is standing.
  it "mutes a sender that was unmuted before" do
    sender = Newsletter::Sender.muting(create(:newsletter, sender_email: "peter@rubyweekly.com"))
    sender.unsilence

    Newsletter::Sender.muting(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    expect(sender.reload).to be_silenced
  end

  # Mail whose From header carried no address at all — Mail parses "From:
  # newsletter" as a one-address list with no address. There is nothing to
  # mute, and a roster row keyed on "" would silence every such sender at
  # once.
  it "mutes nothing when the newsletter carries no address" do
    newsletter = create(:newsletter, sender_email: "")

    Newsletter::Sender.muting(newsletter)

    expect(Newsletter::Sender.count).to be_zero
  end
end
