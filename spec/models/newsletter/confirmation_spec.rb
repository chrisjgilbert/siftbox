require "rails_helper"

RSpec.describe Newsletter::Confirmation do
  def confirmation(subject, sender_email: "no-reply@substack.com")
    Newsletter::Confirmation.new(
      build(:newsletter, subject: subject, sender_email: sender_email)
    )
  end

  it "reads a subject asking the reader to confirm as a confirmation" do
    expect(confirmation("Confirm your subscription")).to be_detected
  end

  it "reads the confirmation noun as a confirmation" do
    expect(confirmation("[Substack] Confirmation required")).to be_detected
  end

  it "reads a subject asking the reader to verify as a confirmation" do
    expect(confirmation("Please verify your email address")).to be_detected
  end

  it "reads the verification noun as a confirmation" do
    expect(confirmation("Your verification link")).to be_detected
  end

  it "reads finishing a signup as a confirmation" do
    expect(confirmation("Finish signing up for The Diff")).to be_detected
  end

  it "reads completing a signup as a confirmation" do
    expect(confirmation("Complete your sign up")).to be_detected
  end

  # Senders write the same phrase three ways in the same email.
  it "reads a hyphenated signup as a confirmation" do
    expect(confirmation("Complete your sign-up")).to be_detected
  end

  it "reads a closed-up signup as a confirmation" do
    expect(confirmation("Complete your signup")).to be_detected
  end

  it "reads activation as a confirmation" do
    expect(confirmation("Activate your subscription")).to be_detected
  end

  it "reads opting in as a confirmation" do
    expect(confirmation("Opt in to keep receiving The Diff")).to be_detected
  end

  it "reads a hyphenated opt-in as a confirmation" do
    expect(confirmation("Opt-in to keep receiving The Diff")).to be_detected
  end

  it "reads a shouted subject as a confirmation" do
    expect(confirmation("CONFIRM YOUR EMAIL ADDRESS")).to be_detected
  end

  it "reads a subject with no confirmation phrase as ordinary mail" do
    expect(confirmation("Issue 742: the new parser")).not_to be_detected
  end

  it "reads an empty subject as ordinary mail" do
    expect(confirmation("")).not_to be_detected
  end

  # The phrases match whole words, which is most of what keeps the set off
  # ordinary newsletter writing: "Confirmed:" opens headlines, and every
  # essay about habits reaches for activation energy sooner or later.
  it "reads a headline about something confirmed as ordinary mail" do
    expect(confirmation("Confirmed: the Fed holds rates")).not_to be_detected
  end

  it "reads a subject about activation as ordinary mail" do
    expect(confirmation("The activation energy of a new habit")).not_to be_detected
  end

  it "reads a subject about verifying claims as ordinary mail" do
    expect(confirmation("Verifying what the S-1 actually says")).not_to be_detected
  end

  # The guard the whole heuristic leans on: an established newsletter is
  # allowed to write about confirmation.
  it "reads a confirmation phrase from an established sender as ordinary mail" do
    create(:newsletter, sender_email: "editor@thediff.co", received_at: 3.days.ago)

    established = Newsletter::Confirmation.new(
      build(:newsletter, subject: "Confirmation bias", sender_email: "editor@thediff.co",
        received_at: 1.hour.ago)
    )

    expect(established).not_to be_detected
  end

  it "reads a confirmation phrase from a sender heard from later as a confirmation" do
    create(:newsletter, sender_email: "editor@thediff.co", received_at: 1.minute.ago)

    earlier = Newsletter::Confirmation.new(
      build(:newsletter, subject: "Confirm your subscription",
        sender_email: "editor@thediff.co", received_at: 1.hour.ago)
    )

    expect(earlier).to be_detected
  end

  it "reads a confirmation phrase from a sender heard from at another address as a confirmation" do
    create(:newsletter, sender_email: "editor@thediff.co", received_at: 3.days.ago)

    expect(confirmation("Confirm your subscription")).to be_detected
  end

  # Every Substack confirmation comes from the same no-reply address, so mail
  # still sitting in the pen cannot be what makes the sender established —
  # the second subscription would never be flagged.
  it "reads a second confirmation from a platform address as a confirmation" do
    create(:newsletter, sender_email: "no-reply@substack.com", received_at: 3.days.ago,
      held_at: 3.days.ago)

    expect(confirmation("Confirm your subscription")).to be_detected
  end

  it "reads a confirmation from an address whose earlier mail was dismissed as a confirmation" do
    create(:newsletter, sender_email: "no-reply@substack.com", received_at: 3.days.ago,
      held_at: 3.days.ago, dismissed_at: 2.days.ago)

    expect(confirmation("Confirm your subscription")).to be_detected
  end

  # Released mail is content, and the reader saying so is the strongest
  # signal there is that this address sends newsletters.
  it "reads a confirmation phrase from an address whose earlier mail was released as ordinary mail" do
    create(:newsletter, sender_email: "no-reply@substack.com", received_at: 3.days.ago,
      held_at: 3.days.ago, released_at: 2.days.ago)

    expect(confirmation("Confirm your subscription")).not_to be_detected
  end

  # Ingest asks after the row is stored, and the backfill asks about rows
  # stored weeks ago. Neither may count the newsletter against itself.
  it "does not count a stored newsletter against itself" do
    stored = create(:newsletter, subject: "Confirm your subscription",
      sender_email: "no-reply@substack.com", received_at: 1.hour.ago)

    expect(Newsletter::Confirmation.new(stored)).to be_detected
  end
end
