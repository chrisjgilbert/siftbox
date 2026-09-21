require "rails_helper"

# Muting from the issue in front of the reader: they are looking at something
# they did not want and are saying so. What it mutes is the sender, not the
# issue — the decision is about who writes, and it reaches the back catalogue
# and whatever arrives next alike.
RSpec.describe "Newsletter silences" do
  it "keeps a signed-out reader from muting a sender" do
    newsletter = create(:newsletter, sender_email: "peter@rubyweekly.com")

    post newsletter_silence_path(newsletter)

    expect(response).to redirect_to(new_session_path)
    expect(Newsletter::Sender.count).to be_zero
  end

  it "mutes the sender of the issue the reader is looking at" do
    sign_in
    newsletter = create(:newsletter, sender_email: "peter@rubyweekly.com")

    post newsletter_silence_path(newsletter)

    expect(Newsletter::Sender.sole).to have_attributes(
      sender_email: "peter@rubyweekly.com", silenced?: true
    )
  end

  # To the roster, because that is the only surface a silence appears on and
  # the reader has just made one. Staying on the original would leave them
  # looking at a page with no sign anything happened.
  it "returns the reader to the roster" do
    sign_in
    newsletter = create(:newsletter, sender_email: "peter@rubyweekly.com")

    post newsletter_silence_path(newsletter)

    expect(response).to redirect_to(subscriptions_url)
  end

  # A second tab open on another issue from the same sender. One address, one
  # roster row, and the first muting's date is the one the roster prints.
  it "keeps one row when two issues from one sender are muted" do
    sign_in
    create(:newsletter, sender_email: "peter@rubyweekly.com")
    post newsletter_silence_path(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    post newsletter_silence_path(create(:newsletter, sender_email: "peter@rubyweekly.com"))

    expect(Newsletter::Sender.count).to eq(1)
  end

  # Mail whose From header carried no address at all. There is nothing to
  # mute, and a roster row keyed on "" would mute every such sender at once —
  # so the button does nothing rather than something wrong.
  it "mutes nothing for an issue carrying no address" do
    sign_in
    newsletter = create(:newsletter, sender_email: "")

    post newsletter_silence_path(newsletter)

    expect(Newsletter::Sender.count).to be_zero
  end

  it "answers 404 for a newsletter that does not exist" do
    sign_in

    post newsletter_silence_path(newsletter_id: 0)

    expect(response).to have_http_status(:not_found)
  end
end
