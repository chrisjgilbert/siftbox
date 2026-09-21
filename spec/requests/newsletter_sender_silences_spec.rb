require "rails_helper"

# The way back, from the roster. Unmuting takes effect from that moment
# onwards: the edition window starts at the watermark, which moved every
# morning of the silence, so the sender rejoins the next edition rather than
# arriving with everything they wrote during it.
RSpec.describe "Newsletter sender silences" do
  it "keeps a signed-out reader from unmuting a sender" do
    sender = create(:newsletter_sender, silenced_at: 1.day.ago)

    delete newsletter_sender_silence_path(sender)

    expect(response).to redirect_to(new_session_path)
    expect(sender.reload).to be_silenced
  end

  it "unmutes a muted sender" do
    sign_in
    sender = create(:newsletter_sender, silenced_at: 1.day.ago)

    delete newsletter_sender_silence_path(sender)

    expect(sender.reload).not_to be_silenced
  end

  it "returns the reader to the roster" do
    sign_in
    sender = create(:newsletter_sender, silenced_at: 1.day.ago)

    delete newsletter_sender_silence_path(sender)

    expect(response).to redirect_to(subscriptions_url)
  end

  # A stale tab, or the reader pressing twice. The roster is the receipt
  # either way and the row is already gone from it.
  it "leaves a sender that is not muted alone" do
    sign_in
    sender = create(:newsletter_sender, silenced_at: nil)

    delete newsletter_sender_silence_path(sender)

    expect(response).to redirect_to(subscriptions_url)
    expect(sender.reload).not_to be_silenced
  end

  it "answers 404 for a sender that does not exist" do
    sign_in

    delete newsletter_sender_silence_path(newsletter_sender_id: 0)

    expect(response).to have_http_status(:not_found)
  end
end
