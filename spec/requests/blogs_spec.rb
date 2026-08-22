require "rails_helper"

RSpec.describe "Blogs" do
  # The fetch is the one thing a request spec cannot let out of the process,
  # so the seam Blog::Subscription takes for its sample is where it stops.
  def feed_answering(document)
    fetched = Blog::Fetch::Fetched.new(document: document, etag: "", last_modified: "")
    allow(Blog::Subscription).to receive(:new).and_wrap_original do |original, blog, **|
      original.call(blog, fetch: ->(_blog) { fetched })
    end
  end

  def article(title)
    <<~ITEM
      <item>
        <title>#{title}</title>
        <link>https://queryplanweekly.dev/#{title.parameterize}</link>
        <guid>#{title.parameterize}</guid>
        <description>#{"word " * 200}</description>
      </item>
    ITEM
  end

  def add(feed_url)
    post blogs_path, params: { blog: { feed_url: feed_url } }
  end

  it "puts a followed blog on the roster" do
    sign_in
    feed_answering(rss_document(article("One")))

    add("https://queryplanweekly.dev/feed")

    expect(Blog.sole.feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  it "returns the reader to the subscriptions page" do
    sign_in
    feed_answering(rss_document(article("One")))

    add("https://queryplanweekly.dev/feed")

    expect(response).to redirect_to(subscriptions_url)
  end

  # Turbo drops the response otherwise, and the form simply stops doing
  # anything — see .claude/rules/controllers.md.
  it "answers a refused feed with the page and an unprocessable status" do
    sign_in
    feed_answering(rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "says why a feed was refused" do
    sign_in
    feed_answering(rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response.body).to include("has nothing in it yet")
  end

  it "keeps the address the reader typed in the form after a refusal" do
    sign_in
    feed_answering(rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response.body).to include("https://queryplanweekly.dev/feed")
  end

  it "takes a blog off the roster" do
    sign_in
    blog = create(:blog)

    delete blog_path(blog)

    expect(Blog.count).to eq(0)
  end

  it "returns the reader to the subscriptions page after removing one" do
    sign_in
    blog = create(:blog)

    delete blog_path(blog)

    expect(response).to redirect_to(subscriptions_url)
  end

  it "keeps a signed-out visitor from adding a blog" do
    add("https://queryplanweekly.dev/feed")

    expect(Blog.count).to eq(0)
  end

  it "keeps a signed-out visitor from removing one" do
    blog = create(:blog)

    delete blog_path(blog)

    expect(Blog.count).to eq(1)
  end
end
