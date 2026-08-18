require "rails_helper"

# The edition read the way it is read: a page, in a browser, found by the words
# on it. The request specs beside this one hold the response body; this holds
# what a reader can see and click.
RSpec.describe "Reading an edition" do
  it "heads the page with the edition's number and the day it covers" do
    edition = create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    sign_in_through_the_form

    visit edition_path(edition)

    expect(page).to have_text("No. 1 · Tuesday 11 August")
  end

  it "prints a lead story and links it to the original it cites" do
    story = create(:edition_story, section: Edition::Story::LEAD,
      headline: "Figma filed its S-1", body: "Levine reads the numbers first.")
    newsletter = create(:newsletter, sender_name: "Money Stuff")
    create(:edition_citation, story: story, newsletter: newsletter)
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_text("Lead stories").and have_text("Figma filed its S-1")
      .and have_text("Levine reads the numbers first.")
      .and have_link("Money Stuff", href: newsletter_original_path(newsletter))
  end

  it "draws the reading list when the window held something evergreen" do
    story = create(:edition_story, section: Edition::Story::READING_LIST,
      headline: "A masterclass in consistent hashing")
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_text("The reading list")
      .and have_text("A masterclass in consistent hashing")
  end

  it "leaves the reading list out, heading and all, when nothing was evergreen" do
    story = create(:edition_story, section: Edition::Story::LEAD)
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).not_to have_text("The reading list")
  end

  # The editor writes prose, and prose contains angle brackets. They reach the
  # page as characters, through ordinary escaping, because a story is written
  # out of mail written by strangers — .claude/rules/security.md.
  it "prints the angle brackets in a story as the characters they are" do
    story = create(:edition_story, body: "Anything under <2GB is a rounding error.")
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_text("Anything under <2GB is a rounding error.")
  end

  it "reaches the archive of editions" do
    edition = create(:edition)
    sign_in_through_the_form
    visit edition_path(edition)

    click_link "Archive"

    expect(page).to have_current_path(editions_path)
  end

  # The nameplate is the way back to today, the way a newspaper's is, so an
  # edition read out of the archive is never a page with no way forward.
  it "returns to the day's briefing from the nameplate" do
    old = create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 12))
    sign_in_through_the_form
    visit edition_path(old)

    click_link "siftbox"

    expect(page).to have_text("No. 2 · Wednesday 12 August")
  end

  it "names the section a story was filed under" do
    story = create(:edition_story, section: Edition::Story::BRIEFLY)
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_text("Briefly")
  end
end
