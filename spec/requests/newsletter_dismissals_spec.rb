require "rails_helper"

# Done: the reader has clicked the sender's confirm button, or has decided the
# hold does not need one. Either way the app never saw the click — the frame is
# an opaque origin — so this POST is the only evidence there is.
RSpec.describe "Newsletter dismissals" do
  it "keeps a signed-out reader from resolving a hold" do
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_dismissal_path(newsletter)

    expect(response).to redirect_to(new_session_path)
    expect(newsletter.reload).not_to be_dismissed
  end

  it "dismisses a held newsletter" do
    sign_in
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_dismissal_path(newsletter)

    expect(newsletter.reload).to be_dismissed
  end

  # Back to the pen, because the reader is working through it and the next row
  # is the next thing they want. The row's absence is the receipt; nothing
  # flashes.
  it "returns the reader to the pen" do
    sign_in
    newsletter = create(:newsletter, held_at: 1.hour.ago)

    post newsletter_dismissal_path(newsletter)

    expect(response).to redirect_to(subscriptions_url)
  end

  # A second tab open on the same original. Newsletter#dismiss is quiet about
  # the repeat, and the first dismissal's stamp is what the phrase set gets
  # judged against later, so it stays.
  it "keeps the first stamp when the hold is dismissed twice" do
    sign_in
    newsletter = create(:newsletter, held_at: 2.hours.ago, dismissed_at: 1.hour.ago)
    dismissed_at = newsletter.dismissed_at

    post newsletter_dismissal_path(newsletter)

    expect(newsletter.reload.dismissed_at).to eq(dismissed_at)
  end

  # The contradiction the state machine raises on: released mail is content,
  # and dismissing it would hide it from the archive it has already rejoined.
  # A stale tab is not worth a 500, so the pen is what it gets.
  it "leaves a newsletter the reader has already released alone" do
    sign_in
    newsletter = create(:newsletter, held_at: 2.hours.ago, released_at: 1.hour.ago)

    post newsletter_dismissal_path(newsletter)

    expect(response).to redirect_to(subscriptions_url)
    expect(newsletter.reload).not_to be_dismissed
  end

  # Nothing in the app posts this, but a form replayed against ordinary mail
  # would stamp a resolution over a hold that never happened — which the
  # validation refuses and the archive would read as a confirmation.
  it "leaves a newsletter that was never held alone" do
    sign_in
    newsletter = create(:newsletter)

    post newsletter_dismissal_path(newsletter)

    expect(newsletter.reload).not_to be_dismissed
  end

  it "answers 404 for a newsletter that does not exist" do
    sign_in

    post newsletter_dismissal_path(newsletter_id: 0)

    expect(response).to have_http_status(:not_found)
  end
end
