require "rails_helper"

RSpec.describe Blog::Post::Presenter do
  it "sends a row to the post" do
    post = build(:blog_post, url: "https://queryplanweekly.dev/unused-index")

    presenter = Blog::Post::Presenter.new(post)

    expect(presenter.path).to eq("https://queryplanweekly.dev/unused-index")
  end

  # A feed item with neither a link nor a permalink guid is stored with no
  # address at all, and an empty href is a link back to the page you are on —
  # so the row would reload the archive rather than open anything.
  it "sends a row with no address of its own to the blog" do
    blog = build(:blog, site_url: "https://queryplanweekly.dev")
    post = build(:blog_post, blog: blog, url: "")

    presenter = Blog::Post::Presenter.new(post)

    expect(presenter.path).to eq("https://queryplanweekly.dev")
  end

  it "falls back to where the feed is fetched from when the blog has no address" do
    blog = build(:blog, site_url: "", feed_url: "https://queryplanweekly.dev/feed")
    post = build(:blog_post, blog: blog, url: "")

    presenter = Blog::Post::Presenter.new(post)

    expect(presenter.path).to eq("https://queryplanweekly.dev/feed")
  end

  it "names the blog as the sender" do
    blog = build(:blog, title: "Query Plan Weekly")

    presenter = Blog::Post::Presenter.new(build(:blog_post, blog: blog))

    expect(presenter.sender).to eq("Query Plan Weekly")
  end
end
