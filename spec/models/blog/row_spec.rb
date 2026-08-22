require "rails_helper"

RSpec.describe Blog::Row do
  it "names the blog by its title" do
    blog = build_stubbed(:blog, title: "Query Plan Weekly")

    expect(Blog::Row.new(blog).name).to eq("Query Plan Weekly")
  end

  # Dan Luu's feed ships an empty <title>, so this is the ordinary case rather
  # than the exotic one.
  it "names a blog that published no title by the feed it is read from" do
    blog = build_stubbed(:blog, title: "", feed_url: "https://danluu.com/atom.xml")

    expect(Blog::Row.new(blog).name).to eq("https://danluu.com/atom.xml")
  end

  it "shows where the feed is read from" do
    blog = build_stubbed(:blog, feed_url: "https://queryplanweekly.dev/feed")

    expect(Blog::Row.new(blog).feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  it "says when the blog was last polled" do
    blog = build_stubbed(:blog, polled_at: 4.minutes.ago, failing_since: nil)

    expect(Blog::Row.new(blog).state).to eq("Checked 4 minutes ago")
  end

  it "says a blog has not been polled yet" do
    blog = build_stubbed(:blog, polled_at: nil, failing_since: nil)

    expect(Blog::Row.new(blog).state).to eq("Not checked yet")
  end

  # The one thing the reader cannot find out any other way: a blog that has
  # stopped being fetchable looks exactly like one that has stopped
  # publishing, and only one of those is worth doing something about.
  it "says how long a failing blog has been failing" do
    blog = build_stubbed(:blog, polled_at: 1.minute.ago, failing_since: 3.days.ago)

    expect(Blog::Row.new(blog).state).to eq("Not answering for 3 days")
  end

  it "is failing when it has been failing" do
    expect(Blog::Row.new(build_stubbed(:blog, failing_since: 3.days.ago))).to be_failing
  end

  it "is not failing when the last poll worked" do
    expect(Blog::Row.new(build_stubbed(:blog, failing_since: nil))).not_to be_failing
  end

  it "counts the posts it has stored" do
    blog = create(:blog)
    create_list(:blog_post, 2, blog: blog)

    expect(Blog::Row.new(blog).count).to eq("2 posts")
  end

  it "counts a single post in the singular" do
    blog = create(:blog)
    create(:blog_post, blog: blog)

    expect(Blog::Row.new(blog).count).to eq("1 post")
  end

  it "draws itself with the blogs row partial" do
    expect(Blog::Row.new(build_stubbed(:blog)).to_partial_path).to eq("blogs/row")
  end
end
