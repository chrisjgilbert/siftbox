require "rails_helper"

# "This is a newsletter": the phrase set misfired and the mail is content after
# all. The release is what carries it into the next edition's window, its
# received_at being behind the watermark by then.
RSpec.describe "Newsletter releases" do
  it "keeps a signed-out reader from resolving a hold" do
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_release_path(newsletter)

    expect(response).to redirect_to(new_session_path)
    expect(newsletter.reload).not_to be_released
  end

  it "releases a held newsletter" do
    sign_in
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_release_path(newsletter)

    expect(newsletter.reload).to be_released
  end

  it "returns the reader to the pen" do
    sign_in
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_release_path(newsletter)

    expect(response).to redirect_to(subscriptions_url)
  end

  # The point of the release, end to end: the archive refuses held mail, and a
  # newsletter the reader has called content reads as though it had never been
  # flagged.
  it "puts the newsletter back into the originals archive" do
    sign_in
    newsletter = create(:newsletter, subject: "Confirmation bias, weekly",
      held_at: 1.hour.ago)

    post newsletter_release_path(newsletter)
    get newsletters_path

    expect(response.body).to include("Confirmation bias, weekly")
  end

  it "keeps the first stamp when the hold is released twice" do
    sign_in
    newsletter = create(:newsletter, held_at: 2.hours.ago, released_at: 1.hour.ago)
    released_at = newsletter.released_at

    post newsletter_release_path(newsletter)

    expect(newsletter.reload.released_at).to eq(released_at)
  end

  # Releasing mail already dismissed is the contradiction from the other side.
  # The validation raises on it; the reader gets the pen instead.
  it "leaves a newsletter the reader has already dismissed alone" do
    sign_in
    newsletter = create(:newsletter, held_at: 2.hours.ago, dismissed_at: 1.hour.ago)

    post newsletter_release_path(newsletter)

    expect(response).to redirect_to(subscriptions_url)
    expect(newsletter.reload).not_to be_released
  end

  # A release stamp on mail that was never held drags ordinary content into a
  # second edition window: Edition::Window picks a newsletter up on when it was
  # released, whatever its received_at says.
  it "leaves a newsletter that was never held alone" do
    sign_in
    newsletter = create(:newsletter)

    post newsletter_release_path(newsletter)

    expect(newsletter.reload).not_to be_released
  end

  it "answers 404 for a newsletter that does not exist" do
    sign_in

    post newsletter_release_path(newsletter_id: 0)

    expect(response).to have_http_status(:not_found)
  end
end
