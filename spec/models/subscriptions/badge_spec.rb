require "rails_helper"

RSpec.describe Subscriptions::Badge do
  it "is pending while a confirmation is waiting" do
    create(:newsletter, held_at: 1.hour.ago)

    expect(Subscriptions::Badge.new).to be_pending
  end

  it "is not pending when nothing has been held" do
    create(:newsletter)

    expect(Subscriptions::Badge.new).not_to be_pending
  end

  # The badge's whole job in failure path 4: it stays until the reader deals
  # with the mail, and goes the moment they do. Either ending clears it.
  it "is not pending once the hold is dismissed" do
    create(:newsletter, held_at: 2.hours.ago, dismissed_at: 1.hour.ago)

    expect(Subscriptions::Badge.new).not_to be_pending
  end

  it "is not pending once the hold is released" do
    create(:newsletter, held_at: 2.hours.ago, released_at: 1.hour.ago)

    expect(Subscriptions::Badge.new).not_to be_pending
  end

  it "counts one waiting confirmation in the singular" do
    create(:newsletter, held_at: 1.hour.ago)

    expect(Subscriptions::Badge.new.line).to eq("1 subscription awaiting confirmation")
  end

  it "counts several in the plural" do
    3.times { create(:newsletter, held_at: 1.hour.ago) }

    expect(Subscriptions::Badge.new.line).to eq("3 subscriptions awaiting confirmation")
  end

  it "points at the page the mail is waiting on" do
    expect(Subscriptions::Badge.new.path).to eq("/subscriptions")
  end

  # The edition page is the one page a reader opens every morning, and it is
  # measured. Asking twice — once whether to draw, once for the words — is one
  # question.
  it "asks the database once however often it is read" do
    create(:newsletter, held_at: 1.hour.ago)
    badge = Subscriptions::Badge.new

    counted = count_queries do
      badge.pending?
      badge.line
    end

    expect(counted).to eq(1)
  end
end
