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

  it "has no newer newsletter when it is the most recent" do
    create(:newsletter, received_at: 3.days.ago)
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(newsletter.newer).to be_nil
  end

  it "requires a received time" do
    expect(build(:newsletter)).to validate_presence_of(:received_at)
  end
end
