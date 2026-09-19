require "rails_helper"

# The public page as a visitor meets it, found by the words on it. The request
# spec beside this one holds the response body; this holds what someone can
# read and click.
RSpec.describe "The landing page" do
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

    expect(page).not_to have_link("Ruby Weekly")
  end
end
