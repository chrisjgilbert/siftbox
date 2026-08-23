require "rails_helper"

RSpec.describe "Blogs" do
  def add(feed_url)
    post blogs_path, params: { blog: { feed_url: feed_url } }
  end

  it "puts a followed blog on the roster" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document(rss_article("One")))

    add("https://queryplanweekly.dev/feed")

    expect(Blog.sole.feed_url).to eq("https://queryplanweekly.dev/feed")
  end

  it "returns the reader to the subscriptions page" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document(rss_article("One")))

    add("https://queryplanweekly.dev/feed")

    expect(response).to redirect_to(subscriptions_url)
  end

  # Turbo drops the response otherwise, and the form simply stops doing
  # anything — see .claude/rules/controllers.md.
  it "answers a refused feed with the page and an unprocessable status" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response).to have_http_status(:unprocessable_entity)
  end

  # The whole message, prefix included: Rails humanises the column to "Feed
  # url", and these sentences are written to follow the label the reader
  # typed into.
  it "says why a feed was refused, by the name the form calls it" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response.body).to include("Feed address has nothing in it yet")
  end

  # The other half of the rule the field is focused by: it holds something,
  # so the cursor belongs in it. A refused reader has one thing to do next
  # and it is here, at the bottom of a long page.
  it "puts the cursor in the field after a refusal" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response.body).to include("autofocus")
  end

  it "keeps the address the reader typed in the form after a refusal" do
    sign_in
    serving("https://queryplanweekly.dev/feed", rss_document)

    add("https://queryplanweekly.dev/feed")

    expect(response.body).to include("https://queryplanweekly.dev/feed")
  end

  it "follows the feed a pasted home page announces" do
    sign_in
    resolve_publicly
    stub_request(:get, "https://queryplanweekly.dev/").to_return(body: home_page("/feed"))
    serving("https://queryplanweekly.dev/feed", rss_document(rss_article("One")))

    add("https://queryplanweekly.dev/")

    expect(Blog.sole.feed_url).to eq("https://queryplanweekly.dev/feed")
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

  # The one endpoint here that dials out on a reader's say-so. Every other
  # create in this app is limited the same way and each of those has an
  # example; this one did not, so the whole declaration could be deleted with
  # the suite still green.
  it "turns away a reader submitting one feed after another" do
    sign_in
    resolve_publicly
    6.times { |index| serving("https://queryplanweekly.dev/feed-#{index}", rss_document(rss_article("One"))) }

    6.times { |index| add("https://queryplanweekly.dev/feed-#{index}") }

    expect(Blog.count).to eq(5)
  end

  it "says why it turned them away" do
    sign_in
    resolve_publicly
    6.times { |index| serving("https://queryplanweekly.dev/feed-#{index}", rss_document(rss_article("One"))) }

    6.times { |index| add("https://queryplanweekly.dev/feed-#{index}") }

    expect(flash[:alert]).to eq("That is a lot of feeds at once. Try again in a minute.")
  end
end
