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

  # Not an SSRF — Download::Destination refuses anything that is not http or
  # https, and refuses it at every redirect hop. This is so a roster row that
  # can never be fetched is refused when it is added, rather than failing
  # silently on every poll forever and reading as a blog that went away.
  it "refuses a feed address a fetch could never follow" do
    expect(build(:blog, feed_url: "file:///etc/passwd")).not_to be_valid
  end

  it "refuses a feed address with no scheme at all" do
    expect(build(:blog, feed_url: "queryplanweekly.dev/feed")).not_to be_valid
  end

  it "accepts an ordinary https feed address" do
    expect(build(:blog, feed_url: "https://queryplanweekly.dev/feed")).to be_valid
  end

  it "accepts a plain http feed address, which plenty of blogs still serve" do
    expect(build(:blog, feed_url: "http://queryplanweekly.dev/feed")).to be_valid
  end

  # Anchored at both ends. Without the end anchor a value could carry a
  # newline and anything after it and still pass, which is what Brakeman's
  # ValidationRegex check is about.
  it "refuses an address carrying a second line behind a valid first one" do
    expect(build(:blog, feed_url: "https://ok.example/feed\njavascript:alert(1)")).not_to be_valid
  end

  it "refuses a scheme with nothing after it" do
    expect(build(:blog, feed_url: "https://")).not_to be_valid
  end

  # A pasted address arrives with whatever whitespace came with it, and the
  # reader typed the useful part.
  it "accepts an address pasted with whitespace around it" do
    blog = create(:blog, feed_url: "  https://queryplanweekly.dev/feed\n")

    expect(blog.feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  # A fact about a blog rather than about a page, which is where it kept
  # ending up: three callers spelled this out, and one of them was a prompt
  # reaching through a display presenter to get it.
  it "is named by its title" do
    expect(build_stubbed(:blog, title: "Query Plan Weekly").name).to eq("Query Plan Weekly")
  end

  # Dan Luu's feed ships <title></title>, so this is the ordinary case.
  it "is named by its feed address when it published no title" do
    blog = build_stubbed(:blog, title: "", feed_url: "https://danluu.com/atom.xml")

    expect(blog.name).to eq("https://danluu.com/atom.xml")
  end
end
