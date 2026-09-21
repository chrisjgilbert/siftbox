require "rails_helper"

# Muting, the way a reader does it: from the issue that made them want to, and
# undone from the roster where the decision is recorded.
RSpec.describe "Muting a source" do
  it "offers to mute the sender from an issue in the archive" do
    newsletter = create(:newsletter, sender_name: "Ruby Weekly")
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).to have_button("Silence this sender")
  end

  # Held mail is not content yet and the two endings a hold has are what the
  # bar is for. A sender the reader never subscribed to is dismissed, not
  # muted.
  it "does not offer to mute from a confirmation still in the pen" do
    newsletter = create(:newsletter, held_at: 1.hour.ago)
    sign_in_through_the_form

    visit newsletter_original_path(newsletter)

    expect(page).to have_no_button("Silence this sender")
  end

  it "mutes the sender and says so on the roster" do
    create(:newsletter, sender_name: "Ruby Weekly", sender_email: "peter@rubyweekly.com")
    sign_in_through_the_form
    visit newsletter_original_path(Newsletter.sole)

    click_button "Silence this sender"

    expect(page).to have_current_path(subscriptions_path)
      .and have_text("Ruby Weekly")
  end

  # Two kinds of row in one list, each drawn through its own template. Rails
  # names the local after the partial, so a mixed roster is the only way to
  # find out that both templates read the local they are actually handed.
  it "draws a blog and a muted sender in one roster" do
    create(:blog, title: "Query Plan Weekly")
    create(:newsletter_sender, name: "Ruby Weekly", silenced_at: 1.day.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_button("Mute Query Plan Weekly")
      .and have_button("Unmute Ruby Weekly")
  end

  it "takes the sender off the roster when unmuted" do
    create(:newsletter_sender, name: "Ruby Weekly",
      sender_email: "peter@rubyweekly.com", silenced_at: 1.day.ago)
    sign_in_through_the_form
    visit subscriptions_path

    click_button "Unmute Ruby Weekly"

    expect(page).to have_no_text("Ruby Weekly")
  end

  it "mutes a blog from the roster" do
    create(:blog, title: "Query Plan Weekly")
    sign_in_through_the_form
    visit subscriptions_path

    click_button "Mute Query Plan Weekly"

    expect(page).to have_button("Unmute Query Plan Weekly")
  end

  # Muting leaves the blog where it is. That is the whole difference from
  # removing, and it is what the roster has to show for the choice to mean
  # anything.
  it "keeps a muted blog on the roster" do
    create(:blog, title: "Query Plan Weekly")
    sign_in_through_the_form
    visit subscriptions_path

    click_button "Mute Query Plan Weekly"

    expect(page).to have_text("Query Plan Weekly")
  end

  # In the row's own words. Read off which way the button points, a muted
  # blog is indistinguishable from an unmuted one to anybody scanning the
  # list — and being able to see what is muted is the whole feature.
  it "says on the row that a blog is muted" do
    create(:blog, title: "Query Plan Weekly", silenced_at: 3.days.ago)
    sign_in_through_the_form

    visit subscriptions_path

    expect(page).to have_text("Muted 3 days ago")
  end

  it "unmutes a blog from the roster" do
    create(:blog, title: "Query Plan Weekly", silenced_at: 1.day.ago)
    sign_in_through_the_form
    visit subscriptions_path

    click_button "Unmute Query Plan Weekly"

    expect(page).to have_button("Mute Query Plan Weekly")
  end
end
