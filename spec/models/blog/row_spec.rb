require "rails_helper"

RSpec.describe Blog::Row do
  it "names the blog by its title" do
    blog = build_stubbed(:blog, title: "Query Plan Weekly")

    expect(Blog::Row.new(blog, 0).name).to eq("Query Plan Weekly")
  end

  # Dan Luu's feed ships an empty <title>, so this is the ordinary case rather
  # than the exotic one.
  it "names a blog that published no title by the feed it is read from" do
    blog = build_stubbed(:blog, title: "", feed_url: "https://danluu.com/atom.xml")

    expect(Blog::Row.new(blog, 0).name).to eq("https://danluu.com/atom.xml")
  end

  it "shows where the feed is read from" do
    blog = build_stubbed(:blog, feed_url: "https://queryplanweekly.dev/feed")

    expect(Blog::Row.new(blog, 0).feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  it "says when the blog was last polled" do
    blog = build_stubbed(:blog, polled_at: 4.minutes.ago, failing_since: nil)

    expect(Blog::Row.new(blog, 0).state).to eq("Checked 4 minutes ago")
  end

  it "says a blog has not been polled yet" do
    blog = build_stubbed(:blog, polled_at: nil, failing_since: nil)

    expect(Blog::Row.new(blog, 0).state).to eq("Not checked yet")
  end

  # The one thing the reader cannot find out any other way: a blog that has
  # stopped being fetchable looks exactly like one that has stopped
  # publishing, and only one of those is worth doing something about.
  it "says how long a failing blog has been failing" do
    blog = build_stubbed(:blog, polled_at: 1.minute.ago, failing_since: 3.days.ago)

    expect(Blog::Row.new(blog, 0).state).to eq("Not answering for 3 days")
  end

  it "is failing when it has been failing" do
    expect(Blog::Row.new(build_stubbed(:blog, failing_since: 3.days.ago), 0)).to be_failing
  end

  it "is not failing when the last poll worked" do
    expect(Blog::Row.new(build_stubbed(:blog, failing_since: nil), 0)).not_to be_failing
  end

  it "counts the posts it was handed" do
    row = Blog::Row.new(build_stubbed(:blog), 2)

    expect(row.count).to eq("2 posts")
  end

  it "counts a single post in the singular" do
    row = Blog::Row.new(build_stubbed(:blog), 1)

    expect(row.count).to eq("1 post")
  end

  it "counts a blog with nothing stored yet" do
    row = Blog::Row.new(build_stubbed(:blog), 0)

    expect(row.count).to eq("0 posts")
  end

  it "draws itself with the blogs row partial" do
    expect(Blog::Row.new(build_stubbed(:blog), 0).to_partial_path).to eq("blogs/row")
  end

  it "marks a failing blog's state line" do
    row = Blog::Row.new(build_stubbed(:blog, failing_since: 3.days.ago), 0)

    expect(row.state_class).to eq("sources__state sources__state--failing")
  end

  it "leaves a healthy blog's state line unmarked" do
    row = Blog::Row.new(build_stubbed(:blog, failing_since: nil), 0)

    expect(row.state_class).to eq("sources__state")
  end

  it "shows the feed address under a blog that has a name of its own" do
    row = Blog::Row.new(build_stubbed(:blog, title: "Query Plan Weekly"), 0)

    expect(row).to be_feed
  end

  # Printing it twice makes one row twice as tall as its neighbours to say one
  # thing.
  it "hides the feed address under a blog already named by it" do
    row = Blog::Row.new(build_stubbed(:blog, title: ""), 0)

    expect(row).not_to be_feed
  end

  # Which way the row's mute button points. Read off the blog rather than
  # decided in the template, the way the state line's class is.
  it "says a muted blog is muted" do
    row = Blog::Row.new(build_stubbed(:blog, silenced_at: 1.day.ago), 0)

    expect(row).to be_silenced
  end

  # In the row's own words, not only in which way its button points. A muted
  # blog otherwise reads exactly like an unmuted one to anybody scanning the
  # list, which is the state the whole feature exists to make visible — and
  # the failing line beside it is the precedent: a condition worth knowing
  # about says itself rather than being inferred from a control.
  it "says how long a muted blog has been muted" do
    row = Blog::Row.new(build_stubbed(:blog, silenced_at: 3.days.ago), 0)

    expect(row.muted).to eq("Muted 3 days ago")
  end

  it "says nothing about muting for a blog nobody has muted" do
    row = Blog::Row.new(build_stubbed(:blog, silenced_at: nil), 0)

    expect(row.muted).to be_nil
  end

  # Both, because both are true and they want different fixing: a muted blog
  # that has also stopped answering is still worth unmuting only once it
  # answers again.
  it "keeps saying a muted blog is failing" do
    row = Blog::Row.new(
      build_stubbed(:blog, silenced_at: 1.day.ago, failing_since: 3.days.ago), 0
    )

    expect(row.state).to eq("Not answering for 3 days")
  end

  it "says a blog nobody has muted is not" do
    row = Blog::Row.new(build_stubbed(:blog, silenced_at: nil), 0)

    expect(row).not_to be_silenced
  end

  it "draws through the template for a blog" do
    row = Blog::Row.new(build_stubbed(:blog), 0)

    expect(row.to_partial_path).to eq("blogs/row")
  end
end
