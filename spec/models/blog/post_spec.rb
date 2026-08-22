require "rails_helper"

RSpec.describe Blog::Post do
  # Rails builds a nested model's table name from the demodulised class name,
  # so the naive answer here is "posts". It prefixes the singular parent table
  # when the parent is itself a model, which is the only reason this lands on
  # the table the migration created. Pinned the way Edition::Story's is, and
  # for the same reason: the day Blog becomes abstract or a plain namespace,
  # the prefix disappears and every query goes to a table that is not there.
  it "stores posts in the blog_posts table" do
    expect(Blog::Post.table_name).to eq("blog_posts")
  end

  it "refuses a post that belongs to no blog" do
    post = Blog::Post.new(received_at: Time.current)

    expect(post).not_to be_valid
  end

  # The column is NOT NULL, so this is about which error the reader of a
  # failure sees: a validation naming the field, rather than a
  # NotNullViolation out of SQLite naming the table.
  it "refuses a post with no arrival time" do
    post = Blog::Post.new(blog: build(:blog), received_at: nil)

    expect(post).not_to be_valid
  end

  # A guid is only unique within the feed that issued it, so two blogs are
  # free to use the same one — and often do, since plenty of generators use
  # the post's path.
  it "allows two blogs to use the same guid" do
    guid = "tag:example,2026:1"
    create(:blog_post, guid: guid)

    second = build(:blog_post, guid: guid)

    expect(second).to be_valid
  end

  # What makes polling the same feed twice store nothing the second time.
  # Enforced by the index rather than by a validation, because two polls
  # running at once both read an empty table before either writes.
  it "refuses two posts from one blog under the same guid" do
    blog = create(:blog)
    create(:blog_post, blog: blog, guid: "tag:example,2026:1")

    expect { create(:blog_post, blog: blog, guid: "tag:example,2026:1") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  # The index is partial, and this is why: "" means the feed named nothing,
  # so without the carve-out every unnamed post a blog publishes would
  # collide with the first one and only one of them could ever be stored.
  it "allows a blog several posts the feed never named" do
    blog = create(:blog)
    create(:blog_post, blog: blog, guid: "")

    second = create(:blog_post, blog: blog, guid: "")

    expect(second).to be_persisted
  end

  # 9 of the 273 posts measured for docs/blogs-rss.md fell under this, mostly
  # Martin Fowler publishing one essay as a run of linked fragments.
  it "is enough to write from when the feed carried the article" do
    post = build_stubbed(:blog_post, body_html: "<p>#{"word " * 200}</p>")

    expect(post).to be_enough_to_write_from
  end

  it "is not enough to write from when the feed carried two lines" do
    post = build_stubbed(:blog_post, body_html: "<p>A note on the planner. More soon.</p>")

    expect(post).not_to be_enough_to_write_from
  end

  # Measured on the same prose the editor would be shown rather than on the
  # HTML, so a post that is mostly markup is judged on what is left of it.
  it "is not enough to write from when the body is markup around nothing" do
    post = build_stubbed(:blog_post, body_html: "<div>#{"<span></span>" * 200}</div>")

    expect(post).not_to be_enough_to_write_from
  end

  it "is not enough to write from when the feed carried no body at all" do
    post = build_stubbed(:blog_post, body_html: "")

    expect(post).not_to be_enough_to_write_from
  end

  # SQLite stops reading a string literal at a NUL, so one stray byte fails
  # the INSERT and loses the post. Feed XML is written by strangers and the
  # parser hands a NUL through intact — confirmed against RSS::REXMLParser
  # rather than assumed.
  it "strips a null byte from a body the feed carried" do
    post = create(:blog_post, body_html: "<p>the#{0.chr} planner</p>")

    expect(post.reload.body_html).to eq("<p>the planner</p>")
  end

  it "strips a null byte from a title the feed carried" do
    post = create(:blog_post, title: "Rewriting#{0.chr} the planner")

    expect(post.reload.title).to eq("Rewriting the planner")
  end

  it "has many attached inline images" do
    expect(build(:blog_post)).to have_many_attached(:inline_images)
  end

  # Served by this app rather than by Active Storage's own routes, which sit
  # outside the authentication gate and never expire.
  it "serves a stored image from a path of its own" do
    post = build_stubbed(:blog_post, id: 7)
    blob = ActiveStorage::Blob.new(id: 3)

    expect(post.inline_image_path(blob)).to eq("/blog_posts/7/images/3")
  end

  # Read again after RemoteImages has rewritten the body, so the archive
  # thumbnail points at this app rather than at the publisher's CDN.
  it "captures the lead image off the body it holds now" do
    post = create(:blog_post, lead_image_url: "https://cdn.example.com/old.png")
    post.update!(body_html: %(<img src="/blog_posts/1/images/2"><p>Words enough to matter.</p>))

    post.capture_lead_image

    expect(post.lead_image_url).to eq("/blog_posts/1/images/2")
  end

  # The factory's contract with the constant, asserted here rather than
  # implied in the eight window and composition examples that depend on it.
  # If it ever slips under, every negative example among those passes for the
  # wrong reason.
  it "is built with enough prose to be written from" do
    expect(build_stubbed(:blog_post)).to be_enough_to_write_from
  end

  # The dedupe key, so a NUL here does not merely fail an INSERT — it changes
  # what "seen this one before" means.
  it "strips a null byte from a guid the feed carried" do
    post = create(:blog_post, guid: "unused#{0.chr}-index")

    expect(post.reload.guid).to eq("unused-index")
  end

  it "strips a null byte from an address the feed carried" do
    post = create(:blog_post, url: "https://queryplanweekly.dev/a#{0.chr}b")

    expect(post.reload.url).to eq("https://queryplanweekly.dev/ab")
  end
end
