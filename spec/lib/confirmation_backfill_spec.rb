require "rails_helper"

RSpec.describe ConfirmationBackfill do
  it "holds stored mail that reads as a confirmation" do
    newsletter = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)

    ConfirmationBackfill.new.hold

    expect(newsletter.reload).to be_held
  end

  it "leaves ordinary stored mail out of the pen" do
    newsletter = create(:newsletter, subject: "Issue 742", received_at: 2.days.ago)

    ConfirmationBackfill.new.hold

    expect(newsletter.reload).not_to be_held
  end

  it "returns the mail it held" do
    newsletter = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)
    create(:newsletter, subject: "Issue 742", received_at: 2.days.ago)

    held = ConfirmationBackfill.new.hold

    expect(held).to eq([ newsletter ])
  end

  # An edition that cites a newsletter links to an original the archive would
  # then refuse to show, and releasing it afterwards would carry it into a
  # second edition. The window an edition covered is history.
  it "leaves mail a published edition has cited out of the pen" do
    newsletter = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)
    create(:edition_citation, newsletter: newsletter)

    ConfirmationBackfill.new.hold

    expect(newsletter.reload).not_to be_held
  end

  it "walks past mail a published edition has cited" do
    newsletter = create(:newsletter, received_at: 2.days.ago)
    create(:edition_citation, newsletter: newsletter)

    expect(ConfirmationBackfill.new.candidates).to be_empty
  end

  it "walks the mail no edition has cited" do
    newsletter = create(:newsletter, received_at: 2.days.ago)

    expect(ConfirmationBackfill.new.candidates).to eq([ newsletter.id ])
  end

  # Both subscriptions confirmed through no-reply@substack.com. The first
  # hold has to land before the second is judged, or the first counts as
  # content and the second is read as an established sender writing about
  # confirmation.
  it "holds a second confirmation from the same platform address" do
    create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 3.days.ago)
    second = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)

    ConfirmationBackfill.new.hold

    expect(second.reload).to be_held
  end

  it "keeps the original hold time when run a second time" do
    newsletter = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)
    ConfirmationBackfill.new.hold
    held_at = newsletter.reload.held_at

    ConfirmationBackfill.new.hold

    expect(newsletter.reload.held_at).to eq(held_at)
  end

  it "holds nothing a second time" do
    create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 2.days.ago)
    ConfirmationBackfill.new.hold

    held = ConfirmationBackfill.new.hold

    expect(held).to be_empty
  end

  # The reader has already ruled on released mail, and re-flagging it would
  # pull it back out of the archive.
  it "leaves mail the reader released out of the pen" do
    newsletter = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 3.days.ago,
      held_at: 2.days.ago, released_at: 1.day.ago)

    ConfirmationBackfill.new.hold

    expect(newsletter.reload).to be_released
  end

  it "leaves mail already waiting in the pen alone" do
    create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 3.days.ago,
      held_at: 2.days.ago)

    held = ConfirmationBackfill.new.hold

    expect(held).to be_empty
  end
end
