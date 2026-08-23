require "rails_helper"

RSpec.describe "Settings" do
  it "keeps a signed-out reader away from the settings page" do
    get settings_path

    expect(response).to redirect_to(new_session_path)
  end

  it "shows the address a subscription should be pointed at" do
    sign_in

    get settings_path

    expect(response.body).to include("newsletters@example.com")
  end

  # Dragged from here to the bookmarks bar. It sits beside the inbound
  # address because it is the same kind of fact: something set up once, here,
  # and used from everywhere else afterwards.
  it "offers a bookmarklet for following the blog you are reading" do
    sign_in

    get settings_path

    expect(response.body).to include("javascript:window.open")
  end
end
