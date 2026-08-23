require "rails_helper"

RSpec.describe "Subscriptions" do
  def pen_of(rows)
    rows.times do |index|
      create(:newsletter, sender_email: "sender#{index}@substack.com",
        held_at: 1.hour.ago)
    end
  end

  # The pen lists senders and subjects out of the reader's own mail, which is
  # the whole of what the gate is protecting.
  it "keeps a signed-out reader away from the pen" do
    create(:newsletter, held_at: 1.hour.ago)

    get subscriptions_path

    expect(response).to redirect_to(new_session_path)
  end

  # Every row prints a sender, a subject and a time. Reading a body to print
  # none of it is what Newsletter::PEN_COLUMNS exists to stop, and the page
  # draws two sections of rows out of one table.
  it "renders a pen row without reading the newsletter's body" do
    sign_in
    create(:newsletter, subject: "Confirm your subscription",
      body_html: "<p>#{'Morning. ' * 200}</p>", held_at: 1.hour.ago)

    get subscriptions_path

    expect(response.body).to include("Confirm your subscription")
    expect(response.body).not_to include("Morning. Morning.")
  end

  # Three sections, three queries, however much is in them. The first request
  # is thrown away because Rails caches the schema and the templates on it.
  # What is held here is that the cost does not move with the size of the pen;
  # the absolute number belongs to Rails.
  it "draws a pen of any size in the same number of queries" do
    sign_in
    pen_of(1)
    get subscriptions_path
    quiet = count_queries { get subscriptions_path }

    pen_of(5)

    expect(count_queries { get subscriptions_path }).to eq(quiet)
  end

  # The roster used to read one COUNT per blog to print "12 posts". What is
  # held here is that the cost does not move with the number of blogs; the
  # absolute number belongs to Rails.
  it "reads a roster of any size in the same number of queries" do
    sign_in
    create(:blog)
    get subscriptions_path
    one_blog = count_queries { get subscriptions_path }

    4.times { create(:blog) }

    expect(count_queries { get subscriptions_path }).to eq(one_blog)
  end

  it "counts the posts each blog has stored" do
    sign_in
    blog = create(:blog, title: "Query Plan Weekly")
    create_list(:blog_post, 2, blog: blog)

    get subscriptions_path

    expect(response.body).to include("2 posts")
  end
end
