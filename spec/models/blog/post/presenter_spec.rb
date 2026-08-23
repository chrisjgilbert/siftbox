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

  # A post was never in an email, so the archive's own placeholder is simply
  # wrong over one.
  it "says an imageless post carried no image" do
    presenter = Blog::Post::Presenter.new(build_stubbed(:blog_post))

    expect(presenter.no_image).to eq("No image in post")
  end

  # link_to does not filter schemes, and a feed writes both of the first two
  # links in this chain. The CSP stops a javascript: URL running today, and
  # the CSP calls itself the second line — on this path it would be the only
  # one.
  # Schemes are case-insensitive, and a feed writing one in capitals is odd
  # rather than hostile. Matched without folding the case, the link was
  # dropped and the row quietly pointed at the blog instead — the same
  # treatment a javascript: URL gets, for a post that had a perfectly good
  # address. Newsletter::LeadImage folds the case on the same list.
  it "follows an address whose scheme the feed wrote in capitals" do
    blog = build_stubbed(:blog)
    post = build_stubbed(:blog_post, blog: blog, url: "HTTPS://queryplanweekly.dev/planner")

    expect(Blog::Post::Presenter.new(post).path).to eq("HTTPS://queryplanweekly.dev/planner")
  end

  it "refuses to point a row at a javascript URL the feed published" do
    blog = build_stubbed(:blog, site_url: "https://queryplanweekly.dev")
    post = build_stubbed(:blog_post, blog: blog, url: "javascript:alert(1)")

    expect(Blog::Post::Presenter.new(post).path).to eq("https://queryplanweekly.dev")
  end

  it "refuses a javascript URL in the blog's own address too" do
    blog = build_stubbed(:blog, site_url: "javascript:alert(1)",
      feed_url: "https://queryplanweekly.dev/feed")
    post = build_stubbed(:blog_post, blog: blog, url: "")

    expect(Blog::Post::Presenter.new(post).path).to eq("https://queryplanweekly.dev/feed")
  end

  it "refuses a data URL, which a browser will still navigate to" do
    blog = build_stubbed(:blog, site_url: "https://queryplanweekly.dev")
    post = build_stubbed(:blog_post, blog: blog, url: "data:text/html,<script>alert(1)</script>")

    expect(Blog::Post::Presenter.new(post).path).to eq("https://queryplanweekly.dev")
  end

  # Plenty of feeds still write these, and they resolve to the publisher's own
  # host exactly as https does.
  it "keeps a protocol-relative address" do
    post = build_stubbed(:blog_post, url: "//queryplanweekly.dev/planner")

    expect(Blog::Post::Presenter.new(post).path).to eq("//queryplanweekly.dev/planner")
  end

  # Rewritten when the format table moved onto Newsletter::Age, and covered by
  # nothing until now: the whole archive row prints through this.
  it "shows the time of day for a post that arrived today" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      post = build_stubbed(:blog_post, received_at: Time.zone.parse("2026-08-06 09:02"))

      expect(Blog::Post::Presenter.new(post).timestamp).to eq("09:02")
    end
  end

  it "shows the day for a post that arrived earlier in the week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      post = build_stubbed(:blog_post, received_at: Time.zone.parse("2026-08-03 09:02"))

      expect(Blog::Post::Presenter.new(post).timestamp).to eq("Mon")
    end
  end

  it "shows the date for a post older than the week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      post = build_stubbed(:blog_post, received_at: Time.zone.parse("2026-06-11 09:02"))

      expect(Blog::Post::Presenter.new(post).timestamp).to eq("11 Jun")
    end
  end
end
