require "rails_helper"

RSpec.describe Feed::Page do
  # A page and one row over, so the boundary cases are about the size the code
  # actually uses rather than about a number invented here.
  def fill(count, received_at: 1.hour.ago)
    Array.new(count) { |n| create(:newsletter, subject: "Issue #{n}", received_at: received_at) }
  end

  it "holds the newest rows first" do
    older = create(:newsletter, received_at: 2.hours.ago)
    newer = create(:newsletter, received_at: 1.hour.ago)

    expect(Feed::Page.new.items).to eq([ newer, older ])
  end

  it "holds mail and posts in one order" do
    create(:newsletter, subject: "Mail", received_at: 2.hours.ago)
    create(:blog_post, title: "Post", received_at: 1.hour.ago)

    expect(Feed::Page.new.items.map(&:class)).to eq([ Blog::Post, Newsletter ])
  end

  it "stops at a page" do
    fill(Feed::Page::SIZE + 5)

    expect(Feed::Page.new.items.length).to eq(Feed::Page::SIZE)
  end

  it "says there is more when a page does not hold everything" do
    fill(Feed::Page::SIZE + 1)

    expect(Feed::Page.new).to be_more
  end

  it "says there is no more when a page holds everything" do
    fill(Feed::Page::SIZE)

    expect(Feed::Page.new).not_to be_more
  end

  it "says there is no more when the archive is empty" do
    expect(Feed::Page.new).not_to be_more
  end

  # The whole point of the cursor. Page two starts below the row page one
  # ended on, with nothing shown twice and nothing skipped between them.
  it "carries on from where the last page ended" do
    fill(Feed::Page::SIZE + 5)
    first = Feed::Page.new

    second = Feed::Page.new(after: first.last)

    expect(second.items.length).to eq(5)
    expect(second.items & first.items).to be_empty
  end

  it "accounts for every row across two pages" do
    fill(Feed::Page::SIZE + 5)
    first = Feed::Page.new

    second = Feed::Page.new(after: first.last)

    expect((first.items + second.items).map(&:id).uniq.length).to eq(Feed::Page::SIZE + 5)
  end

  # Date headers carry whole seconds, so a batch send lands every row on one
  # instant. The order has to stay total across that, or paging re-shows one
  # row and drops another.
  it "pages through rows that all arrived on the same instant" do
    landed = 1.hour.ago
    fill(Feed::Page::SIZE + 5, received_at: landed)
    first = Feed::Page.new

    second = Feed::Page.new(after: first.last)

    expect((first.items + second.items).map(&:id).uniq.length).to eq(Feed::Page::SIZE + 5)
  end

  # And across two tables, where the id alone stops being comparable:
  # newsletter 5 and post 5 are different rows with the same number.
  #
  # The counts are lopsided on purpose. Split evenly, every id holds exactly
  # two rows and the page boundary always falls between a pair, so a cursor
  # missing the kind loses nothing and the example passes against the bug it
  # was written for. Twenty-five and thirty-six puts the boundary on the
  # first of a pair — page one ends on newsletter 6, post 6 is the next row —
  # and a cursor comparing the id alone drops it.
  it "pages through mail and posts that arrived on the same instant" do
    landed = 1.hour.ago
    25.times { create(:newsletter, received_at: landed) }
    36.times { create(:blog_post, received_at: landed) }
    first = Feed::Page.new

    second = Feed::Page.new(after: first.last)

    expect(first.items.length + second.items.length).to eq(61)
    expect(second.items & first.items).to be_empty
  end

  it "has nothing to carry on from when the archive is empty" do
    expect(Feed::Page.new.last).to be_nil
  end

  # Mail landing while the reader is paging belongs above the cursor, so it
  # cannot push a row they have already seen onto the next page. That is the
  # difference between a cursor and an offset.
  it "is unmoved by mail arriving while the reader pages" do
    fill(Feed::Page::SIZE + 5)
    cursor = Feed::Page.new.last
    standing = Feed::Page.new(after: cursor).items.map(&:id)

    create(:newsletter, subject: "Just landed", received_at: Time.current)

    expect(Feed::Page.new(after: cursor).items.map(&:id)).to eq(standing)
  end

  # .content, so the pen's mail stays off the archive the way it always has.
  # Written here rather than trusted from Feed, because the page builds its
  # own SQL and a scope it forgot would be silent.
  it "leaves out mail held as a subscription confirmation" do
    create(:newsletter, received_at: 2.hours.ago, held_at: 1.hour.ago)

    expect(Feed::Page.new.items).to be_empty
  end

  it "leaves out a confirmation that was dismissed" do
    create(:newsletter, received_at: 3.hours.ago, held_at: 2.hours.ago,
      dismissed_at: 1.hour.ago)

    expect(Feed::Page.new.items).to be_empty
  end

  it "holds a newsletter released back out of the pen" do
    released = create(:newsletter, received_at: 3.hours.ago, held_at: 2.hours.ago,
      released_at: 1.hour.ago)

    expect(Feed::Page.new.items).to eq([ released ])
  end

  # The archive reaches all the way back now. A seven-day window was what
  # stopped it answering the question it exists for — finding something weeks
  # later, outside any edition.
  it "reaches past the week the feed used to stop at" do
    old = create(:newsletter, received_at: 40.days.ago)

    expect(Feed::Page.new.items).to eq([ old ])
  end

  it "reads a post's blog without a query per row" do
    create_list(:blog_post, 3)
    page = Feed::Page.new
    posts = page.items

    expect(count_queries { posts.each { |post| post.blog.name } }).to be_zero
  end

  # Bodies run to hundreds of kilobytes and the index never prints one.
  it "leaves the bodies behind" do
    create(:newsletter, body_html: "<p>Morning</p>")

    expect { Feed::Page.new.items.first.body_html }
      .to raise_error(ActiveModel::MissingAttributeError)
  end
end
