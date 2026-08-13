require "rails_helper"

RSpec.describe Edition::Story do
  # Rails builds a nested model's table name from the demodulised class name,
  # so the naive answer here is "stories". It prefixes the singular parent
  # table when the parent is itself a model, which is the only reason this
  # lands on the table the migration created. Pinned because the day someone
  # makes Edition an abstract class or moves Story under a plain module, the
  # prefix silently disappears and every query goes to a table that isn't
  # there.
  it "stores stories in the edition_stories table" do
    expect(Edition::Story.table_name).to eq("edition_stories")
  end

  it "belongs to an edition" do
    expect(build(:edition_story)).to belong_to(:edition)
  end

  it "requires a position" do
    expect(build(:edition_story)).to validate_presence_of(:position)
  end

  it "requires a section" do
    expect(build(:edition_story)).to validate_presence_of(:section)
  end

  it "requires a body" do
    expect(build(:edition_story)).to validate_presence_of(:body)
  end

  it "refuses a section the edition page has nowhere to render" do
    story = build(:edition_story, section: "editorial")

    expect(story).not_to be_valid
  end

  it "refuses a position another story in the same edition already holds" do
    edition = create(:edition)
    create(:edition_story, edition: edition, position: 1)

    story = build(:edition_story, edition: edition, position: 1)

    expect(story).not_to be_valid
  end

  it "allows the same position in another edition" do
    create(:edition_story, edition: create(:edition, published_on: Date.new(2026, 8, 11)), position: 1)

    story = build(:edition_story, edition: create(:edition, published_on: Date.new(2026, 8, 12)), position: 1)

    expect(story).to be_valid
  end

  it "cites the newsletters its citations point at" do
    story = create(:edition_story)
    newsletter = create(:newsletter)
    create(:edition_citation, story: story, newsletter: newsletter)

    expect(story.newsletters).to eq([ newsletter ])
  end

  it "takes its citations with it when destroyed" do
    story = create(:edition_story)
    create(:edition_citation, story: story)

    story.destroy

    expect(Edition::Citation.count).to eq(0)
  end

  # A citation is a fact about the edition, not about the newsletter, so
  # clearing an edition away leaves the archive of originals untouched.
  it "leaves the newsletters it cited behind when destroyed" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    story.destroy

    expect(Newsletter.count).to eq(1)
  end

  it "orders by position" do
    edition = create(:edition)
    second = create(:edition_story, edition: edition, position: 2)
    first = create(:edition_story, edition: edition, position: 1)

    expect(Edition::Story.in_position_order).to eq([ first, second ])
  end

  it "is a lead when it sits in the lead section" do
    story = build_stubbed(:edition_story, section: Edition::Story::LEAD)

    expect(story).to be_lead
  end

  it "is not a lead when it sits in another section" do
    story = build_stubbed(:edition_story, section: Edition::Story::BRIEFLY)

    expect(story).not_to be_lead
  end

  it "is a briefly item when it sits in the briefly section" do
    story = build_stubbed(:edition_story, section: Edition::Story::BRIEFLY)

    expect(story).to be_briefly
  end

  it "is not a briefly item when it sits in another section" do
    story = build_stubbed(:edition_story, section: Edition::Story::LEAD)

    expect(story).not_to be_briefly
  end

  it "is a reading list entry when it sits in the reading list section" do
    story = build_stubbed(:edition_story, section: Edition::Story::READING_LIST)

    expect(story).to be_reading_list
  end

  it "is not a reading list entry when it sits in another section" do
    story = build_stubbed(:edition_story, section: Edition::Story::LEAD)

    expect(story).not_to be_reading_list
  end

  # The shape composition builds: the whole graph in memory, saved at the end.
  # Citation's own uniqueness check reads the table, so it sees nothing here.
  it "refuses to cite the same newsletter twice before either is saved" do
    newsletter = create(:newsletter)
    story = build(:edition_story)
    story.citations.build(newsletter: newsletter)
    story.citations.build(newsletter: newsletter)

    expect(story).not_to be_valid
  end

  it "allows one story to cite two different newsletters" do
    story = build(:edition_story)
    story.citations.build(newsletter: create(:newsletter))
    story.citations.build(newsletter: create(:newsletter))

    expect(story).to be_valid
  end
end
