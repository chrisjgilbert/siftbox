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

  # A lead written off six sources runs to six hundred words, and the page
  # used to set every one of them in a single element. The editor's own
  # breaks now reach the page as paragraphs.
  #
  # By selector, which .claude/rules/testing.md allows where nothing else
  # will do: what is being held here is the shape of the copy, and a
  # paragraph has no accessible name to find it by.
  it "sets a lead written in paragraphs as paragraphs" do
    story = create(:edition_story, section: Edition::Story::LEAD,
      body: "Levine reads the numbers first.\n\nThe Diff reads the filing instead.")
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_css("p.story__paragraph", count: 2)
  end

  it "sets a list the editor wrote as a list" do
    story = create(:edition_story, section: Edition::Story::READING_LIST,
      body: "It covers three things:\n- Sharding\n- Retries\n- Backpressure")
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_css("li.story__bullet", count: 3).and have_text("Backpressure")
  end

  # The marker is the page's and it is drawn in CSS, so the hyphen the editor
  # typed is never read back to the reader as punctuation.
  it "leaves the list marker out of the copy" do
    story = create(:edition_story, body: "- Sharding")
    sign_in_through_the_form

    visit edition_path(story.edition)

    expect(page).to have_text("Sharding").and have_no_text("- Sharding")
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
