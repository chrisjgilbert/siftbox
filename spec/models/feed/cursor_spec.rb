require "rails_helper"

RSpec.describe Feed::Cursor do
  it "takes its place from the newsletter it was made for" do
    newsletter = create(:newsletter, received_at: Time.utc(2026, 8, 11, 9))

    cursor = Feed::Cursor.new(newsletter)

    expect(cursor).to have_attributes(
      kind: "Newsletter", id: newsletter.id, received_at: Time.utc(2026, 8, 11, 9)
    )
  end

  it "takes its place from the post it was made for" do
    post = create(:blog_post, received_at: Time.utc(2026, 8, 11, 9))

    expect(Feed::Cursor.new(post).kind).to eq("Blog::Post")
  end

  # What the Older link carries. Two plain parameters rather than one encoded
  # string, so the address says what it means and nothing has to be parsed
  # back out of it.
  it "goes into a link as the kind and the id" do
    newsletter = create(:newsletter)

    expect(Feed::Cursor.new(newsletter).to_query)
      .to eq({ after_kind: "Newsletter", after_id: newsletter.id })
  end

  it "reads a newsletter back out of the parameters it was linked with" do
    newsletter = create(:newsletter, received_at: Time.utc(2026, 8, 11, 9))

    cursor = Feed::Cursor.from("Newsletter", newsletter.id)

    expect(cursor.received_at).to eq(Time.utc(2026, 8, 11, 9))
  end

  it "reads a post back out of the parameters it was linked with" do
    post = create(:blog_post, received_at: Time.utc(2026, 8, 11, 9))

    expect(Feed::Cursor.from("Blog::Post", post.id).received_at)
      .to eq(Time.utc(2026, 8, 11, 9))
  end

  it "is nothing when no cursor was asked for" do
    expect(Feed::Cursor.from(nil, nil)).to be_nil
  end

  # An address the reader edited, or a link to a row since removed. The first
  # page is the honest answer — better than a 404 on an archive, and better
  # than a page bounded by a row that is not there.
  it "is nothing when the row it names has gone" do
    expect(Feed::Cursor.from("Newsletter", 0)).to be_nil
  end

  # The kind names a class this app then loads from. Left to the parameter it
  # is an instruction to constantize whatever a stranger put in a URL, so it
  # is matched against the two kinds the archive holds and nothing else.
  it "is nothing for a kind the archive does not hold" do
    expect(Feed::Cursor.from("User", 1)).to be_nil
  end

  it "is nothing for a kind that names no class at all" do
    expect(Feed::Cursor.from("Kernel#system", 1)).to be_nil
  end

  it "is nothing when the id is not a number" do
    create(:newsletter)

    expect(Feed::Cursor.from("Newsletter", "; DROP TABLE newsletters")).to be_nil
  end
end
