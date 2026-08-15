require "rails_helper"

# The notice the edition page carries while something is in the pen. The
# edition is the page a reader opens every morning, which is the only reason
# it is here: a confirm link that expires in a day or two has to be seen on
# the page the reader was going to open anyway.
RSpec.describe "The edition page's pen notice" do
  it "says one subscription is waiting" do
    create(:edition)
    create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form

    visit root_path

    expect(page).to have_text("1 subscription awaiting confirmation")
  end

  # Rails' own pluralisation, not a conditional in a template: one and three
  # are different sentences.
  it "says how many are waiting when there is more than one" do
    create(:edition)
    3.times { create(:newsletter, held_at: 1.hour.ago) }
    sign_in_through_the_form

    visit root_path

    expect(page).to have_text("3 subscriptions awaiting confirmation")
  end

  it "opens the pen from the notice" do
    create(:edition)
    create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form
    visit root_path

    click_link "1 subscription awaiting confirmation"

    expect(page).to have_current_path(subscriptions_path)
  end

  # State, not a flash. Failure path 4 is a hold nobody actions until the link
  # expires, so the notice has to survive every page load until the mail is
  # resolved — it cannot be scrolled away or cleared by reading it.
  it "is still there on the next visit" do
    edition = create(:edition)
    create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form
    visit edition_path(edition)

    visit edition_path(edition)

    expect(page).to have_text("1 subscription awaiting confirmation")
  end

  it "goes when the reader resolves the hold" do
    edition = create(:edition)
    newsletter = create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form
    visit newsletter_original_path(newsletter)
    click_button "Done"

    visit edition_path(edition)

    expect(page).not_to have_text("awaiting confirmation")
  end

  # Root serves the editions archive on a morning before the first edition
  # exists — which is exactly the morning a reader is subscribing to things
  # and the pen is at its busiest. The notice follows them there rather than
  # being absent on the one day it is most needed.
  it "carries the notice on the archive before any edition exists" do
    create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form

    visit root_path

    expect(page).to have_text("1 subscription awaiting confirmation")
  end

  it "says nothing on a morning with nothing waiting" do
    edition = create(:edition)
    create(:newsletter)
    sign_in_through_the_form

    visit edition_path(edition)

    expect(page).not_to have_text("awaiting confirmation")
  end
end
