require "rails_helper"

RSpec.describe "The landing page" do
  it "shows the project page to a signed-out visitor" do
    get root_path

    expect(response.body).to include("One edition, every morning")
  end

  # Opening the app should land on the day's briefing, not on the page that
  # describes it. The edition is the app; the originals are an archive behind
  # it.
  it "sends a signed-in reader to the latest edition" do
    sign_in
    create(:edition, published_on: Date.new(2026, 8, 11))
    today = create(:edition, published_on: Date.new(2026, 8, 12))

    get root_path

    expect(response).to redirect_to(edition_url(today))
  end

  # Day one, and any morning after a run that found nothing to compose: there
  # is no edition to serve. The archive is the page that says when to expect
  # one, which is a better answer than the inbox the edition replaced.
  it "sends a signed-in reader to the archive before there is an edition" do
    sign_in

    get root_path

    expect(response).to redirect_to(editions_url)
  end

  # The one page in this app meant to be found. Everything behind the sign-in
  # gate keeps the noindex tag the layout emits by default.
  it "lets the landing page be indexed" do
    get root_path

    expect(response.body).not_to include(%(name="robots"))
  end
end
