require "rails_helper"

RSpec.describe Blog::Bookmarklet do
  # Fired from somebody else's blog, where nothing knows where siftbox lives.
  it "points at this app's own follow form" do
    expect(Blog::Bookmarklet.new.href).to include("http://example.com/subscriptions")
  end

  # Kept in a bookmarks bar for good, so the host it records has to be the one
  # this app answers on rather than the one the reader happened to be looking
  # at. Taken from the request, a bookmarklet dragged once from localhost
  # during setup would open localhost every time after.
  it "carries the host this app answers on, not the request's" do
    expect(Blog::Bookmarklet.new.href).not_to include("test.host")
  end

  # Blogs publish addresses with query strings in them often enough. Handed
  # over raw, everything after the first ampersand would arrive as siftbox's
  # own parameters and the rest of the address would be lost.
  it "hands the page over encoded" do
    expect(Blog::Bookmarklet.new.href).to include("encodeURIComponent(location.href)")
  end

  # The opened tab keeps a live reference back to the blog otherwise, and a
  # third-party script on that page can steer a tab it holds — at a sign-in
  # form on what the reader believes is a tab they opened themselves.
  it "severs the opener on the tab it opens" do
    expect(Blog::Bookmarklet.new.href).to include("noopener")
  end

  # The section is the last thing on a long page, so without this the reader
  # lands nowhere near the address they just sent over.
  it "lands on the section rather than the top of the page" do
    expect(Blog::Bookmarklet.new.href).to include("##{Blog::Bookmarklet::ANCHOR}")
  end
end
