require "rails_helper"

# The public page read the way a visitor reads it: found by the words on it and
# the links in it. The request spec beside this one holds the response and where
# a signed-in reader is sent; this holds what a visitor can see and follow.
RSpec.describe "The landing page" do
  it "offers the source from the nav" do
    visit root_path

    # exact: true, because the matcher is otherwise a substring match and "Read
    # the source" in the closing band would satisfy it.
    expect(page).to have_link("Source", exact: true,
      href: "https://github.com/chrisjgilbert/siftbox")
  end

  it "offers the source to a visitor" do
    visit root_path

    expect(page).to have_link("Read the source",
      href: "https://github.com/chrisjgilbert/siftbox")
  end

  it "names the one way in" do
    visit root_path

    expect(page).to have_text("Run a copy")
  end

  # There is no hosted instance, so the page asks for nothing and stores
  # nothing. The only thing it wants from a visitor is that they read it.
  it "asks a visitor for nothing" do
    visit root_path

    expect(page).not_to have_field("Email")
  end

  it "shows an edition in the product shot" do
    visit root_path

    expect(page).to have_text("Lead stories")
      .and have_text("Ruby 3.5 preview ships with the new parser on by default")
  end

  # The shot is a picture made of markup. A name in it that looked like a link
  # would promise a page that does not exist, on the one page in the app a
  # stranger sees first.
  it "keeps the shot's sources as text, not links" do
    visit root_path

    expect(page).to have_text("Ruby Weekly")
    expect(page).not_to have_link("Ruby Weekly")
  end
end
