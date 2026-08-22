require "rails_helper"

RSpec.describe Blog do
  it "refuses a blog with no feed address" do
    blog = Blog.new(feed_url: "")

    expect(blog).not_to be_valid
  end

  # One row per feed, because a blog followed twice is the same posts stored
  # twice under two identities — and nothing downstream would be able to tell
  # the duplicates apart.
  it "refuses a second blog at the same feed address" do
    Blog.create!(feed_url: "https://queryplanweekly.dev/feed")

    duplicate = Blog.new(feed_url: "https://queryplanweekly.dev/feed")

    expect(duplicate).not_to be_valid
  end
end
