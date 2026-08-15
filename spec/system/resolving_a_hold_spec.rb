require "rails_helper"

# The loop the PRD traces: a confirmation lands, the pen holds it, the reader
# opens the sender's own email, clicks the sender's own confirm button, and
# then tells this app what it could not see.
RSpec.describe "Resolving a held confirmation" do
  def held_confirmation
    create(:newsletter, sender_name: "Substack",
      sender_email: "no-reply@substack.com",
      subject: "Confirm your subscription to The Diff",
      received_at: 4.minutes.ago, held_at: 4.minutes.ago)
  end

  # A sender the archive already knew, so the confirmation is listed under
  # Awaiting confirmation and not also under New senders. Held mail from a
  # genuinely first-time sender appears in both sections deliberately, which
  # is what makes the link ambiguous to click.
  def earlier_mail_from(sender_email)
    create(:newsletter, sender_email: sender_email, subject: "Issue 1",
      received_at: 3.weeks.ago)
  end

  it "offers both endings on a held original" do
    newsletter = held_confirmation
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).to have_button("Done").and have_button("This is a newsletter")
  end

  # The archive's bar goes back to the reader. A confirmation is not in the
  # archive at all, so the way back from it is the pen.
  it "sends the reader back to the pen rather than to the archive" do
    newsletter = held_confirmation
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).to have_link("Back to subscriptions", href: subscriptions_path)
    expect(page).not_to have_link("Back to the reader")
  end

  it "keeps the archive's bar on an original that was never held" do
    newsletter = create(:newsletter)
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).to have_link("Back to the reader")
    expect(page).not_to have_button("Done")
  end

  # Nothing observes the confirm click — the frame is an opaque origin with no
  # scripts — so Done is the reader saying so, and the row leaving the pen is
  # the only receipt there is.
  it "clears the row out of the pen when the reader is done" do
    earlier_mail_from("no-reply@substack.com")
    held_confirmation
    sign_in_through_the_form
    visit subscriptions_path
    click_link "Confirm your subscription to The Diff"

    click_button "Done"

    expect(page).to have_current_path(subscriptions_path)
    expect(page).to have_text("Nothing waiting")
  end

  # The misfire, caught from the same bar: an established newsletter whose
  # subject read like a confirmation goes back to being content.
  it "puts a misfire back into the originals archive" do
    earlier_mail_from("matt@bloomberg.net")
    create(:newsletter, sender_name: "Money Stuff",
      sender_email: "matt@bloomberg.net",
      subject: "Confirmation bias, weekly", held_at: 1.hour.ago)
    sign_in_through_the_form
    visit subscriptions_path
    click_link "Confirmation bias, weekly"

    click_button "This is a newsletter"

    expect(page).to have_current_path(subscriptions_path)
    expect(page).to have_text("Nothing waiting")
  end

  it "shows the released newsletter in the archive again" do
    newsletter = create(:newsletter, subject: "Confirmation bias, weekly",
      held_at: 1.hour.ago)
    sign_in_through_the_form
    visit newsletter_original_path(newsletter)

    click_button "This is a newsletter"
    visit newsletters_path

    expect(page).to have_text("Confirmation bias, weekly")
  end

  # Resolved is resolved: the bar on a dismissed original is the archive's
  # again, so a reader cannot post a second, contradicting ending from a page
  # left open.
  it "drops the pen bar once the hold is resolved" do
    newsletter = create(:newsletter, held_at: 2.hours.ago, dismissed_at: 1.hour.ago)
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).not_to have_button("Done")
  end
end
