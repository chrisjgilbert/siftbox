require "rails_helper"

RSpec.describe Newsletter::Sender::Row do
  it "names the sender by what they called themselves" do
    sender = build_stubbed(:newsletter_sender, name: "Ruby Weekly")

    expect(Newsletter::Sender::Row.new(sender).name).to eq("Ruby Weekly")
  end

  # A From header need not carry a display name, and the address is the only
  # other thing this app knows about the sender — the same fallback Blog#name
  # makes to its feed address.
  it "names the sender by their address when they gave no name" do
    sender = build_stubbed(:newsletter_sender, name: "",
      sender_email: "peter@rubyweekly.com")

    expect(Newsletter::Sender::Row.new(sender).name).to eq("peter@rubyweekly.com")
  end

  # The one thing a reader wants from this row that the name does not give:
  # how long it has been like that. The distance rather than the clock time,
  # for the reason Blog::Row prints it that way.
  it "says how long the sender has been muted" do
    sender = build_stubbed(:newsletter_sender, silenced_at: 3.days.ago)

    expect(Newsletter::Sender::Row.new(sender).state).to eq("Muted 3 days ago")
  end

  it "answers to the sender's own address" do
    sender = create(:newsletter_sender)

    expect(Newsletter::Sender::Row.new(sender).to_param).to eq(sender.to_param)
  end

  # Its own template, because a muted sender has no feed, no poll state and no
  # stored count — the three things a blog's row is mostly made of.
  it "draws through a template of its own" do
    sender = build_stubbed(:newsletter_sender)

    expect(Newsletter::Sender::Row.new(sender).to_partial_path)
      .to eq("newsletter_senders/row")
  end
end
