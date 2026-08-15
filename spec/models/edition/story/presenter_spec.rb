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
end
