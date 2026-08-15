require "rails_helper"

RSpec.describe "Editions" do
  it "keeps a signed-out reader away from the archive" do
    create(:edition)

    get editions_path

    expect(response).to redirect_to(new_session_path)
  end

  # The archive prints the number and the day in columns of their own rather
  # than as the one masthead line the edition page carries.
  it "lists every edition in the archive" do
    sign_in
    create(:edition, number: 1, published_on: Date.new(2026, 8, 11))
    create(:edition, number: 2, published_on: Date.new(2026, 8, 12))

    get editions_path

    expect(response.body).to include("No. 1").and include("Tuesday 11 August")
      .and include("No. 2").and include("Wednesday 12 August")
  end

  it "opens each archive line onto its edition" do
    sign_in
    edition = create(:edition)

    get editions_path

    expect(response.body).to include(edition_path(edition))
  end

  # Before the first morning, and after a run that found nothing to compose,
  # there is no edition at all. The page says so rather than drawing an empty
  # list.
  it "says so when no edition has been published yet" do
    sign_in

    get editions_path

    expect(response.body).to include("No editions yet")
  end

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

  # Each story's citations used to fire a query of their own the first time
  # the page touched them, so an edition of fifteen stories cost fifteen extra
  # queries. What is being held here is that the cost does not move with the
  # size of the edition; the absolute number belongs to Rails.
  it "reads an edition of any size in the same number of queries" do
    sign_in
    quiet_day = edition_of(1)
    busy_day = edition_of(6)
    get edition_path(quiet_day)

    counted = [ count_queries { get edition_path(quiet_day) },
                count_queries { get edition_path(busy_day) } ]

    expect(counted.last).to eq(counted.first)
  end

  # The notice is app chrome and has to be unmistakably that: it sits outside
  # the edition, above everything the editor wrote, where the masthead and the
  # nav are. Nothing the model produced reaches it — it is a count and a
  # locale string — and nothing about it may ever read as a story.
  it "carries the pen notice outside the edition itself" do
    sign_in
    edition = create(:edition)
    create(:newsletter, held_at: 1.hour.ago)

    get edition_path(edition)

    expect(response.body.index("awaiting confirmation"))
      .to be < response.body.index(%(<main class="edition">))
  end

  # Milestone 4 measured this page at five statements. The notice adds one —
  # a COUNT riding index_newsletters_on_held_at, which is partial on exactly
  # the rows it counts — and six is what an empty pen, one hold and five holds
  # all cost. What is held here is that the cost does not move with the pen;
  # the absolute number belongs to Rails.
  it "reads a pen of any depth in the same number of queries" do
    sign_in
    edition = create(:edition)
    create(:newsletter, held_at: 1.hour.ago)
    get edition_path(edition)
    shallow = count_queries { get edition_path(edition) }

    5.times { create(:newsletter, held_at: 1.hour.ago) }

    expect(count_queries { get edition_path(edition) }).to eq(shallow)
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

  # An edition whose every story cites a newsletter of its own, which is the
  # shape the citation queries scale with.
  def edition_of(stories)
    edition = create(:edition)
    stories.times do |index|
      story = create(:edition_story, edition: edition, position: index + 1)
      create(:edition_citation, story: story, newsletter: create(:newsletter))
    end

    edition
  end
end
