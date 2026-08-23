require "rails_helper"

RSpec.describe Edition::Story::Presenter do
  it "reads the editor's headline" do
    story = build_stubbed(:edition_story, headline: "Figma filed")

    expect(Edition::Story::Presenter.new(story).headline).to eq("Figma filed")
  end

  it "reads the editor's copy" do
    story = build_stubbed(:edition_story, body: "Money Stuff and The Diff both read it.")

    expect(Edition::Story::Presenter.new(story).body).to eq("Money Stuff and The Diff both read it.")
  end

  # The column defaults to "" and a Briefly line is short enough that the
  # editor can leave it at that. The page draws no empty heading over one.
  it "has a headline when the editor wrote one" do
    story = build_stubbed(:edition_story, headline: "Figma filed")

    expect(Edition::Story::Presenter.new(story)).to be_headline
  end

  it "has no headline when the editor left it empty" do
    story = build_stubbed(:edition_story, headline: "")

    expect(Edition::Story::Presenter.new(story)).not_to be_headline
  end

  it "is cited when the editor named a source" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    expect(Edition::Story::Presenter.new(story)).to be_cited
  end

  it "is uncited when the editor named none" do
    story = create(:edition_story)

    expect(Edition::Story::Presenter.new(story)).not_to be_cited
  end

  it "labels a single source in the singular" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    expect(Edition::Story::Presenter.new(story).sources_label).to eq("Source")
  end

  it "labels several sources in the plural" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    expect(Edition::Story::Presenter.new(story).sources_label).to eq("Sources")
  end

  it "names the sender behind each citation" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter, sender_name: "Money Stuff"))

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:sender)).to eq([ "Money Stuff" ])
  end

  # The one destination a citation and an archive row share: the sender's own
  # HTML, sandboxed. Never the reader.
  it "points each citation at the original" do
    story = create(:edition_story)
    newsletter = create(:newsletter)
    create(:edition_citation, story: story, newsletter: newsletter)

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:path)).to eq([ "/newsletters/#{newsletter.id}/original" ])
  end

  it "names a citation whose mail carried no sender at all" do
    story = create(:edition_story)
    create(:edition_citation, story: story,
      newsletter: create(:newsletter, sender_name: "", sender_email: ""))

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:sender)).to eq([ "Unknown sender" ])
  end

  it "cites nothing for a story the editor attributed to nothing" do
    story = create(:edition_story)

    expect(Edition::Story::Presenter.new(story).sources).to be_empty
  end

  it "names the blog behind a post citation" do
    story = create(:edition_story)
    blog = create(:blog, title: "Query Plan Weekly")
    create(:edition_citation, story: story, newsletter: nil,
      blog_post: create(:blog_post, blog: blog))

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:sender)).to eq([ "Query Plan Weekly" ])
  end

  # The post's own page, which is a post's only honest original: nothing here
  # was ever sent to us, so there is no stored copy to sandbox.
  it "points a post citation at the post itself" do
    story = create(:edition_story)
    post = create(:blog_post, url: "https://queryplanweekly.dev/planner")
    create(:edition_citation, story: story, newsletter: nil, blog_post: post)

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:path)).to eq([ "https://queryplanweekly.dev/planner" ])
  end

  # The link leaves this app for somebody else's site, so it opens where the
  # archive row's does — and noopener, which is the one thing target=_blank
  # gives away for free.
  it "opens a post citation in a new tab" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: nil, blog_post: create(:blog_post))

    source = Edition::Story::Presenter.new(story).sources.sole

    expect(source.attributes).to eq(target: "_blank", rel: "noopener noreferrer")
  end

  # A newsletter's original is served by this app, in the sandboxed frame. It
  # stays in the tab it was opened from.
  it "keeps a newsletter citation in the same tab" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))

    source = Edition::Story::Presenter.new(story).sources.sole

    expect(source.attributes).to be_empty
  end

  it "is cited when the editor named only a post" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: nil, blog_post: create(:blog_post))

    expect(Edition::Story::Presenter.new(story)).to be_cited
  end

  it "counts mail and posts together when labelling the sources" do
    story = create(:edition_story)
    create(:edition_citation, story: story, newsletter: create(:newsletter))
    create(:edition_citation, story: story, newsletter: nil, blog_post: create(:blog_post))

    expect(Edition::Story::Presenter.new(story).sources_label).to eq("Sources")
  end

  it "lists the mail it cited before the posts" do
    story = create(:edition_story)
    blog = create(:blog, title: "Query Plan Weekly")
    create(:edition_citation, story: story, newsletter: nil,
      blog_post: create(:blog_post, blog: blog))
    create(:edition_citation, story: story, newsletter: create(:newsletter, sender_name: "Money Stuff"))

    sources = Edition::Story::Presenter.new(story).sources

    expect(sources.map(&:sender)).to eq([ "Money Stuff", "Query Plan Weekly" ])
  end
end
