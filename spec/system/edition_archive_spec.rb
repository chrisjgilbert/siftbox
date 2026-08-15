require "rails_helper"

# The archive the way a reader uses it: every edition there has been, in an
# order the page states out loud, each line opening the edition behind it.
RSpec.describe "The archive of editions" do
  it "lists an edition by its number and the day it covers" do
    edition = create(:edition, number: 4, published_on: Date.new(2026, 8, 11))
    sign_in_through_the_form

    visit editions_path

    expect(page).to have_link("No. 4", href: edition_path(edition))
      .and have_text("Tuesday 11 August")
  end

  # Numbering follows composition order and the archive sorts by the day
  # covered, so an edition backfilled for an earlier day reads No. 1, No. 3,
  # No. 2. Decided rather than open — which puts the burden on the page to
  # say which of the two it is ordered by.
  it "says the list is ordered by the day covered" do
    create(:edition)
    sign_in_through_the_form

    visit editions_path

    expect(page).to have_text("By the day covered")
  end

  it "files an edition composed late under the day it covers" do
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 13))
    create(:edition, number: 3, published_on: Date.new(2026, 8, 12))
    sign_in_through_the_form

    visit editions_path

    expect(page.text).to match(/No\. 2.*No\. 3.*No\. 1/m)
  end

  it "counts what it holds" do
    create(:edition)
    create(:edition)
    sign_in_through_the_form

    visit editions_path

    expect(page).to have_text("2 editions")
  end

  it "opens an edition from its line" do
    create(:edition, number: 4, published_on: Date.new(2026, 8, 11))
    sign_in_through_the_form
    visit editions_path

    click_link "No. 4"

    expect(page).to have_text("No. 4 · Tuesday 11 August")
  end

  it "reaches the archive of originals" do
    sign_in_through_the_form
    visit editions_path

    click_link "Originals"

    expect(page).to have_current_path(newsletters_path)
  end

  it "reaches the day's briefing from the nameplate" do
    create(:edition, number: 4, published_on: Date.new(2026, 8, 11))
    sign_in_through_the_form
    visit editions_path

    click_link "siftbox"

    expect(page).to have_text("No. 4 · Tuesday 11 August")
  end

  # Before the first morning, and after a run that found nothing to compose,
  # there is no edition at all. Root sends a signed-in reader here on such a
  # morning, so this line is the whole of what the app has to say.
  it "says so when there is no edition yet" do
    sign_in_through_the_form

    visit editions_path

    expect(page).to have_text("No editions yet")
  end
end
