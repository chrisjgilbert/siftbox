require "rails_helper"

# The pen, read the way a reader reads it after subscribing to something: what
# is waiting to be confirmed, who has written for the first time, and what the
# spam gate refused on the way in.
RSpec.describe "The Subscriptions page" do
  # The one thing on this page that is not a newsletter. Action Mailbox stores
  # the raw source and marks the record bounced; the page reads the sender and
  # the subject back out of it.
  def refuse(from:, subject:)
    ActionMailbox::InboundEmail.create_and_extract_message_id!(
      "From: #{from}\nTo: news@example.com\nSubject: #{subject}\n\nAlmost there",
      status: :bounced
    )
  end

  it "lists a held confirmation with how long ago it landed" do
    newsletter = create(:newsletter, sender_name: "Substack",
      subject: "Confirm your subscription to The Diff",
      received_at: 4.minutes.ago, held_at: 4.minutes.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Awaiting confirmation")
      .and have_link("Confirm your subscription to The Diff",
        href: newsletter_original_path(newsletter))
      .and have_text("4 minutes ago")
  end

  # The confirm click needs the sender's own HTML, which is why the row opens
  # the original rather than the reader: the iframe there is sandboxed with
  # allow-popups precisely so their button works.
  #
  # The sender wrote three weeks ago too, which keeps this confirmation out of
  # New senders and the link unambiguous. Held mail from a first-time sender —
  # the ordinary case — is deliberately listed in both sections.
  it "opens a held confirmation onto the sender's own email" do
    create(:newsletter, sender_email: "no-reply@substack.com",
      received_at: 3.weeks.ago)
    create(:newsletter, sender_email: "no-reply@substack.com",
      subject: "Confirm your subscription to The Diff",
      received_at: 4.minutes.ago, held_at: 4.minutes.ago)
    sign_in_through_the_form
    visit subscriptions_path

    click_link "Confirm your subscription to The Diff"

    expect(page).to have_text("Original HTML, sandboxed in an iframe")
  end

  it "says nothing is waiting when the pen is empty" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Nothing waiting")
  end

  # The net for a confirmation the phrase set missed. An unflagged first email
  # is the case that matters: nothing else on the page would show it.
  it "lists a first-time sender that was never flagged" do
    newsletter = create(:newsletter, sender_name: "The Diff",
      subject: "Issue 1: what this newsletter is for",
      received_at: 2.days.ago, held_at: nil)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("New senders")
      .and have_link("Issue 1: what this newsletter is for",
        href: newsletter_original_path(newsletter))
  end

  it "leaves out a sender the archive already knew" do
    create(:newsletter, sender_email: "peter@rubyweekly.com",
      subject: "Issue 741", received_at: 5.weeks.ago)
    create(:newsletter, sender_email: "peter@rubyweekly.com",
      subject: "Issue 742", received_at: 1.day.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).not_to have_text("Issue 742")
  end

  it "says no address has written when none has" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("No address has written for the first time")
  end

  # The one truly silent drop in the pipeline. The spam gate bounces before a
  # newsletter row exists, so this section is the only place it is ever seen.
  it "lists what the spam gate refused" do
    refuse(from: "Ghost <no-reply@ghost.io>", subject: "Please confirm your email")
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Recently bounced").and have_text("Ghost")
      .and have_text("Please confirm your email")
  end

  it "says nothing was refused when nothing was" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Nothing refused")
  end

  # Every section is drawn whether or not it has anything in it. A pen that
  # disappears when empty cannot answer "did my subscription arrive?" — the
  # question a reader comes here to ask when nothing is waiting.
  it "draws all three sections on a page with nothing on it" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Awaiting confirmation").and have_text("New senders")
      .and have_text("Recently bounced")
  end

  it "is reached from the masthead of any page behind the gate" do
    sign_in_through_the_form
    visit editions_path

    click_link "Subscriptions"

    expect(page).to have_current_path(subscriptions_path)
  end
end
