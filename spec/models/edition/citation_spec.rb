require "rails_helper"

RSpec.describe Edition::Citation do
  it "stores citations in the edition_citations table" do
    expect(Edition::Citation.table_name).to eq("edition_citations")
  end

  it "belongs to a story" do
    expect(build(:edition_citation)).to belong_to(:story).class_name("Edition::Story")
  end

  it "belongs to a newsletter" do
    expect(build(:edition_citation)).to belong_to(:newsletter)
  end

  # The column is edition_story_id, but the association is :story, and Rails
  # derives "story_id" from the name. Reading the story back is what proves
  # the two have been introduced.
  it "reads back the story it joins" do
    story = create(:edition_story)

    citation = create(:edition_citation, story: story)

    expect(citation.reload.story).to eq(story)
  end

  it "refuses to cite the same newsletter twice in one story" do
    newsletter = create(:newsletter)
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: newsletter)

    citation = build(:edition_citation, story: story, newsletter: newsletter)

    expect(citation).not_to be_valid
  end

  # Four newsletters covering one story is the case the edition exists for,
  # and a newsletter covering four topics is cited in four stories.
  it "allows two stories to cite one newsletter" do
    newsletter = create(:newsletter)
    edition = create(:edition)
    create(:edition_citation, story: create(:edition_story, edition: edition), newsletter: newsletter)

    citation = build(:edition_citation, story: create(:edition_story, edition: edition), newsletter: newsletter)

    expect(citation).to be_valid
  end

  it "allows one story to cite two newsletters" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    citation = build(:edition_citation, story: story, newsletter: create(:newsletter))

    expect(citation).to be_valid
  end
end
