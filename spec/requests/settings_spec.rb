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
end
