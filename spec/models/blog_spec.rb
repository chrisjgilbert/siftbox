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

  it "records the time when a poll fails" do
    blog = create(:blog, polled_at: nil, failing_since: nil)

    blog.poll_failed

    expect(blog.polled_at).to be_present
    expect(blog.failing_since).to be_present
  end

  # The first failure's time survives the ones after it, which is what lets
  # the Sources page say how long a blog has been broken rather than only
  # that it is.
  it "keeps the first failure's time through a second failure" do
    first = 3.days.ago
    blog = create(:blog, failing_since: first)

    blog.poll_failed

    expect(blog.failing_since).to be_within(1.second).of(first)
  end
end
