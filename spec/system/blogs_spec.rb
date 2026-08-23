require "rails_helper"

# The roster, read and written the way a reader does it: paste a feed, see it
# arrive, take one off again. It sits on the Subscriptions page because that
# is where the reader already goes to see what reaches them and what does not.
RSpec.describe "The blogs on the Subscriptions page" do
  include ActiveJob::TestHelper

  # The reading happens off the request, so the reader is told yes or no at
  # once and the row fills in behind them. Both halves are what they see, so
  # both happen here.
  def follow(feed_url)
    fill_in "Feed address", with: feed_url
    perform_enqueued_jobs { click_button "Follow" }
  end

  it "says the roster is empty before anything is on it" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Blogs").and have_text("No blogs yet")
  end

  it "puts a followed blog on the roster with what it read" do
    serving("https://queryplanweekly.dev/feed",
      rss_document(rss_article("One") + rss_article("Two")),
      rss_document(rss_article("One") + rss_article("Two")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://queryplanweekly.dev/feed")
    visit subscriptions_path

    expect(page).to have_text("Query Plan Weekly").and have_text("2 posts")
  end

  # The whole reason the check is made while the reader is standing there:
  # refusing later, silently, tells them nothing.
  it "refuses a link aggregator and says why" do
    serving("https://news.ycombinator.com/rss",
      rss_document(aggregated("One") + aggregated("Two")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://news.ycombinator.com/rss")

    expect(page).to have_text("looks like a link aggregator")
  end

  it "keeps the address in the form after refusing it" do
    serving("https://news.ycombinator.com/rss", rss_document(aggregated("One")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://news.ycombinator.com/rss")

    expect(page).to have_field("Feed address", with: "https://news.ycombinator.com/rss")
  end

  it "takes a blog off the roster" do
    create(:blog, title: "Query Plan Weekly")
    sign_in_through_the_form

    visit subscriptions_path
    click_button "Remove"

    expect(page).to have_text("No blogs yet")
  end

  it "says how long a blog has not been answering" do
    create(:blog, title: "Query Plan Weekly", polled_at: 1.minute.ago,
      failing_since: 3.days.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Not answering for 3 days")
  end

  it "says a blog has not been checked yet" do
    create(:blog, title: "Query Plan Weekly", polled_at: nil)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Not checked yet")
  end

  # Readers know their blogs by their home pages. Most sites never show a feed
  # address at all, so pasting one is the case, not the exception.
  it "follows the feed a pasted home page announces" do
    resolve_publicly
    stub_request(:get, "https://queryplanweekly.dev/").to_return(body: home_page("/feed"))
    serving("https://queryplanweekly.dev/feed",
      rss_document(rss_article("One")), rss_document(rss_article("One")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://queryplanweekly.dev/")
    visit subscriptions_path

    expect(page).to have_text("https://queryplanweekly.dev/feed").and have_text("1 post")
  end

  # Filled but deliberately not focused, even though this is the one thing the
  # reader came here to do.
  #
  # A filled field one keystroke from following is a link any page can hand a
  # signed-in reader: "press Enter to continue" on a page linking here with
  # feed_url set, and the follow goes through as an ordinary first-party POST
  # carrying the reader's own cookie and token. What gets followed then
  # fetches from inside the network and puts a stranger's writing in front of
  # the editor every morning after.
  it "does not put the cursor in a field filled from the query" do
    sign_in_through_the_form

    visit subscriptions_path(feed_url: "https://queryplanweekly.dev/")

    expect(find_field("Feed address")["autofocus"]).to be_nil
  end

  # What the field actually needed was the scroll, and an anchor moves the
  # viewport without moving the cursor. The section is the last thing on a
  # long page, so a reader arriving from a bookmarklet would otherwise land
  # nowhere near the address they just sent over.
  it "names the section a bookmarklet scrolls to" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_css("section#blogs")
  end

  # The one case where the cursor does belong in it: the reader submitted an
  # address themselves and it came back refused, so the one thing to do next
  # is here.
  it "puts the cursor in the field after a refusal" do
    serving("https://news.ycombinator.com/rss", rss_document(aggregated("One")))
    sign_in_through_the_form

    visit subscriptions_path
    follow("https://news.ycombinator.com/rss")

    expect(find_field("Feed address")["autofocus"]).to eq("autofocus")
  end

  it "leaves the cursor alone on an ordinary visit" do
    sign_in_through_the_form

    visit subscriptions_path

    expect(find_field("Feed address")["autofocus"]).to be_nil
  end

  # rack_test runs no JavaScript, so the dialog cannot be driven — but the
  # attribute can be held. Without it the button was deleted-and-still-green,
  # on the one irreversible cascade in this app.
  it "asks before removing a blog, because its posts and citations go too" do
    create(:blog, title: "Query Plan Weekly")
    sign_in_through_the_form

    visit subscriptions_path

    expect(find_button("Remove")["data-turbo-confirm"]).to include("Query Plan Weekly")
  end

  # Every row's button says "Remove", so a reader who cannot see which row
  # they are in has nothing to tell three of them apart.
  it "names the blog on each row's Remove button" do
    create(:blog, title: "Query Plan Weekly")
    create(:blog, title: "The Diff", feed_url: "https://thediff.co/feed")
    sign_in_through_the_form

    visit subscriptions_path

    expect(page.all("button").map { |button| button["aria-label"] })
      .to include("Remove Query Plan Weekly", "Remove The Diff")
  end
end
