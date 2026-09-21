require "rails_helper"

# Paging back, the way a reader does it when they are looking for something
# they remember arriving a while ago. The archive stopped at seven days before
# this, which is the one job the PRD gives it that it could not do.
RSpec.describe "Paging the originals archive" do
  def fill(count)
    Array.new(count) do |n|
      create(:newsletter, subject: "Issue #{n}", received_at: n.hours.ago)
    end
  end

  it "reaches the page below from the end of this one" do
    issues = fill(Feed::Page::SIZE + 1)
    sign_in_through_the_form
    visit newsletters_path

    click_link "Older"

    expect(page).to have_text(issues.last.subject)
  end

  it "leaves the rows it has already shown behind" do
    issues = fill(Feed::Page::SIZE + 1)
    sign_in_through_the_form
    visit newsletters_path

    click_link "Older"

    expect(page).to have_no_text(issues.first.subject)
  end

  it "offers no way back from the end of the archive" do
    fill(Feed::Page::SIZE + 1)
    sign_in_through_the_form
    visit newsletters_path

    click_link "Older"

    expect(page).to have_no_link("Older")
  end

  it "says where the archive ends once there is nothing below" do
    fill(Feed::Page::SIZE + 1)
    sign_in_through_the_form
    visit newsletters_path

    click_link "Older"

    expect(page).to have_text("End of feed — #{Feed::Page::SIZE + 1} items")
  end

  # Past the week Newsletter::Age names, the headings are months. "Earlier /
  # This week" over mail from June is a heading that lies, and the archive
  # reaches back that far now.
  it "heads older mail with the month it arrived in" do
    travel_to Time.zone.parse("2026-08-06 18:00")
    create(:newsletter, subject: "From June", received_at: Time.zone.parse("2026-06-14 09:00"))
    sign_in_through_the_form

    visit newsletters_path

    expect(page).to have_text("June").and have_text("2026")
  end

  it "keeps this week's own headings above the months" do
    travel_to Time.zone.parse("2026-08-06 18:00")
    create(:newsletter, received_at: 2.hours.ago)
    create(:newsletter, received_at: Time.zone.parse("2026-06-14 09:00"))
    sign_in_through_the_form

    visit newsletters_path

    expect(page.text).to match(/Today.*June/m)
  end
end
