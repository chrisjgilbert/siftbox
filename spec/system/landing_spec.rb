require "rails_helper"

# The public page read the way a visitor reads it: found by the words on it and
# the links in it. The request specs beside this one hold the switch's two
# states and the response body; this holds what a visitor can see and follow.
RSpec.describe "The landing page" do
  it "offers the source from the nav" do
    open_the_waitlist

    visit root_path

    # exact: true, because the matcher is otherwise a substring match and "Read
    # the source" in the closing band would satisfy it.
    expect(page).to have_link("Source", exact: true,
      href: "https://github.com/chrisjgilbert/siftbox")
  end

  it "names both ways in" do
    open_the_waitlist

    visit root_path

    expect(page).to have_text("Want an address?").and have_text("Or run your own")
  end

  it "offers the source to a visitor" do
    open_the_waitlist

    visit root_path

    expect(page).to have_link("Read the source",
      href: "https://github.com/chrisjgilbert/siftbox")
  end

  it "shows an edition in the product shot" do
    open_the_waitlist

    visit root_path

    expect(page).to have_text("Lead stories")
      .and have_text("Ruby 3.5 preview ships with the new parser on by default")
  end

  # The shot is a picture made of markup. A name in it that looked like a link
  # would promise a page that does not exist, on the one page in the app a
  # stranger sees first.
  it "keeps the shot's sources as text, not links" do
    open_the_waitlist

    visit root_path

    expect(page).to have_text("Ruby Weekly")
    expect(page).not_to have_link("Ruby Weekly")
  end

  # The page draws the form twice, in the hero and in the closing band, so a
  # bare fill_in "Email" is ambiguous. The hero is scoped by what it is and what
  # it says rather than by a class — :element locates an element by its own name,
  # and Capybara 3.40 has no :section selector to say the same thing shorter.
  it "still takes a signup" do
    open_the_waitlist
    visit root_path

    within(:element, "section", text: "Your morning edition") do
      fill_in "Email", with: "reader@example.com"
      click_button "Join the waitlist"
    end

    expect(page).to have_text("On the list")
  end
end
