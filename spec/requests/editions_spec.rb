require "rails_helper"

RSpec.describe "Editions" do
  it "keeps a signed-out reader away from an edition" do
    edition = create(:edition)

    get edition_path(edition)

    expect(response).to redirect_to(new_session_path)
  end

  it "heads the edition with its number and the day it covers" do
    sign_in
    edition = create(:edition, number: 1, published_on: Date.new(2026, 8, 11))

    get edition_path(edition)

    expect(response.body).to include("No. 1 · Tuesday 11 August")
  end

  it "prints the editor's headline" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "Figma filed its S-1")

    get edition_path(edition)

    expect(response.body).to include("Figma filed its S-1")
  end

  it "prints the editor's copy" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, body: "Levine reads the numbers first.")

    get edition_path(edition)

    expect(response.body).to include("Levine reads the numbers first.")
  end

  it "heads each section the edition filled" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::BRIEFLY)

    get edition_path(edition)

    expect(response.body).to include("Briefly")
  end

  it "leaves out the heading of a section the edition has nothing for" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, section: Edition::Story::LEAD)

    get edition_path(edition)

    expect(response.body).not_to include("The reading list")
  end

  it "links a citation to the sender's original" do
    sign_in
    edition = create(:edition)
    newsletter = create(:newsletter)
    create(:edition_citation, story: create(:edition_story, edition: edition), newsletter: newsletter)

    get edition_path(edition)

    expect(response.body).to include(newsletter_original_path(newsletter))
  end

  it "names the sender behind a citation" do
    sign_in
    edition = create(:edition)
    create(:edition_citation, story: create(:edition_story, edition: edition),
      newsletter: create(:newsletter, sender_name: "Money Stuff"))

    get edition_path(edition)

    expect(response.body).to include("Money Stuff")
  end

  # The model's words are the model's words. They reach the page through
  # ordinary escaping and there is no html_safe path anywhere near them —
  # see .claude/rules/security.md and the PRD.
  it "escapes a headline the model wrote as markup" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, headline: "<script>alert(1)</script>")

    get edition_path(edition)

    expect(response.body).not_to include("<script>alert(1)</script>")
  end

  it "escapes copy the model wrote as markup" do
    sign_in
    edition = create(:edition)
    create(:edition_story, edition: edition, body: "<script>alert(1)</script>")

    get edition_path(edition)

    expect(response.body).not_to include("<script>alert(1)</script>")
  end

  it "answers 404 for an edition that was never published" do
    sign_in

    get edition_path(id: 0)

    expect(response).to have_http_status(:not_found)
  end

  it "keeps an edition out of search indexes" do
    sign_in
    edition = create(:edition)

    get edition_path(edition)

    expect(response.body).to include(%(<meta name="robots" content="noindex, nofollow">))
  end
end
