require "rails_helper"

RSpec.describe ApplicationHelper do
  # The mark thickens as it shrinks, so the brackets still read at favicon
  # scale. Four steps, from the design handoff's compensation table.
  it "draws the mark at its lightest weight above thirty pixels" do
    expect(helper.mark_stroke_width(64)).to eq(4)
  end

  it "thickens the mark a step in the twenties" do
    expect(helper.mark_stroke_width(24)).to eq(5)
  end

  it "thickens the mark again at twenty pixels" do
    expect(helper.mark_stroke_width(20)).to eq(6)
  end

  it "draws the mark at its heaviest weight at favicon scale" do
    expect(helper.mark_stroke_width(16)).to eq(7)
  end

  # Dragged to a bookmarks bar and fired from somebody else's blog, where
  # nothing knows where siftbox lives.
  it "points the bookmarklet at this app's own follow form" do
    expect(helper.follow_bookmarklet).to include("http://example.com/subscriptions")
  end

  # Kept in a bookmarks bar for good, so the host it records has to be the
  # one this app answers on rather than the one the reader happened to be
  # looking at. Taken from the request, a bookmarklet dragged once from
  # localhost during setup would open localhost every time after.
  it "carries the host this app answers on, not the request's" do
    expect(helper.follow_bookmarklet).not_to include("test.host")
  end

  # The opened tab keeps a live reference back to the blog otherwise, and a
  # third-party script on that page can steer it — at a sign-in form on what
  # the reader believes is a tab they opened themselves.
  it "severs the opener on the tab it opens" do
    expect(helper.follow_bookmarklet).to include("noopener")
  end

  # Blogs publish addresses with query strings in them often enough. Handed
  # over raw, everything after the first ampersand would arrive as siftbox's
  # own parameters and the rest of the address would be lost.
  it "hands the page over encoded" do
    expect(helper.follow_bookmarklet).to include("encodeURIComponent(location.href)")
  end
end
