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

  # A citation is rendered as a sender's name and a link. Bodies run to
  # hundreds of kilobytes, and an edition's forty-odd citations would be tens
  # of megabytes read to print forty names.
  it "leaves the sender's own HTML out of a citation" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter, body_html: "<p>Hi</p>"))

    cited = story.newsletters.sole

    expect { cited.body_html }.to raise_error(ActiveModel::MissingAttributeError)
  end

  it "leaves the sender's own HTML out of a citation loaded ahead of time" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter, body_html: "<p>Hi</p>"))

    cited = Edition::Story.includes(:newsletters).find(story.id).newsletters.sole

    expect { cited.body_html }.to raise_error(ActiveModel::MissingAttributeError)
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

  it "cites the blog posts its citations point at" do
    story = create(:edition_story)
    post = create(:blog_post)
    create(:edition_citation, story: story, newsletter: nil, blog_post: post)

    expect(story.blog_posts).to eq([ post ])
  end

  # The same reasoning as the newsletter above: a post's body_html is the
  # whole article, and the page prints the blog's name.
  it "leaves the post's own HTML out of a citation" do
    story = create(:edition_story)
    post = create(:blog_post, body_html: "<p>Hi</p>")
    create(:edition_citation, story: story, newsletter: nil, blog_post: post)

    cited = story.blog_posts.sole

    expect { cited.body_html }.to raise_error(ActiveModel::MissingAttributeError)
  end

  it "leaves the posts it cited behind when destroyed" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: nil, blog_post: create(:blog_post))

    story.destroy

    expect(Blog::Post.count).to eq(1)
  end

  # The graph the editor builds is in memory and unsaved, so neither the
  # unique index nor Citation's own uniqueness validation can see the
  # duplicate. Same hole as the newsletter side, same floor under it.
  it "refuses a story citing one post twice" do
    post = create(:blog_post)
    story = build(:edition_story)
    story.citations.build(newsletter: nil, blog_post: post)
    story.citations.build(newsletter: nil, blog_post: post)

    expect(story).not_to be_valid
  end

  it "allows one story to cite two different posts" do
    story = build(:edition_story)
    story.citations.build(newsletter: nil, blog_post: create(:blog_post))
    story.citations.build(newsletter: nil, blog_post: create(:blog_post))

    expect(story).to be_valid
  end

  # Every mail citation leaves blog_post_id NULL, and every post citation
  # leaves newsletter_id NULL. Neither is a duplicate of the other, and a
  # check written as "the ids are distinct" would call three of either a
  # duplicate on the nils alone.
  it "allows one story to cite a newsletter and two posts" do
    story = build(:edition_story)
    story.citations.build(newsletter: create(:newsletter))
    story.citations.build(newsletter: nil, blog_post: create(:blog_post))
    story.citations.build(newsletter: nil, blog_post: create(:blog_post))

    expect(story).to be_valid
  end

  # The presenter documents this order and until now nothing provided it: the
  # rendered order was whichever index SQLite happened to reach for, so a
  # preloaded edition and a lazily-loaded one listed one story's sources
  # differently — and making the mail index partial, to match the post one,
  # would silently re-order every published edition.
  it "reads its cited newsletters oldest first" do
    story = create(:edition_story)
    newer = create(:newsletter, received_at: 1.hour.ago)
    older = create(:newsletter, received_at: 2.hours.ago)
    create(:edition_citation, story: story, newsletter: newer)
    create(:edition_citation, story: story, newsletter: older)

    expect(story.newsletters).to eq([ older, newer ])
  end

  it "reads its cited posts oldest first" do
    story = create(:edition_story)
    newer = create(:blog_post, received_at: 1.hour.ago)
    older = create(:blog_post, received_at: 2.hours.ago)
    create(:edition_citation, story: story, newsletter: nil, blog_post: newer)
    create(:edition_citation, story: story, newsletter: nil, blog_post: older)

    expect(story.blog_posts).to eq([ older, newer ])
  end

  it "reads its cited posts in the same order when they are preloaded" do
    story = create(:edition_story)
    newer = create(:blog_post, received_at: 1.hour.ago)
    older = create(:blog_post, received_at: 2.hours.ago)
    create(:edition_citation, story: story, newsletter: nil, blog_post: newer)
    create(:edition_citation, story: story, newsletter: nil, blog_post: older)

    loaded = Edition.for_reading.find(story.edition_id).stories.sole

    expect(loaded.blog_posts).to eq([ older, newer ])
  end
end
