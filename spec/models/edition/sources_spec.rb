require "rails_helper"

RSpec.describe Edition::Sources do
  it "keeps the newsletters it was given" do
    newsletter = build_stubbed(:newsletter)

    sources = Edition::Sources.new(newsletters: [ newsletter ], posts: [])

    expect(sources.newsletters).to eq([ newsletter ])
  end

  it "keeps the posts it was given" do
    post = build_stubbed(:blog_post)

    sources = Edition::Sources.new(newsletters: [], posts: [ post ])

    expect(sources.posts).to eq([ post ])
  end

  it "is empty when it holds neither" do
    sources = Edition::Sources.new(newsletters: [], posts: [])

    expect(sources).to be_empty
  end

  it "is not empty when it holds only mail" do
    sources = Edition::Sources.new(newsletters: [ build_stubbed(:newsletter) ], posts: [])

    expect(sources).not_to be_empty
  end

  it "is not empty when it holds only posts" do
    sources = Edition::Sources.new(newsletters: [], posts: [ build_stubbed(:blog_post) ])

    expect(sources).not_to be_empty
  end
end
