require "rails_helper"

RSpec.describe Subscriptions::Row do
  it "names the sender" do
    row = Subscriptions::Row.new(build_stubbed(:newsletter, sender_name: "Substack"))

    expect(row.sender).to eq("Substack")
  end

  # Through Newsletter::Presenter, so mail with no From header at all reads
  # here the way it reads in the archive rather than as a blank line.
  it "names mail with no sender at all" do
    row = Subscriptions::Row.new(
      build_stubbed(:newsletter, sender_name: "", sender_email: "")
    )

    expect(row.sender).to eq("Unknown sender")
  end

  it "prints the subject" do
    row = Subscriptions::Row.new(build_stubbed(:newsletter, subject: "Confirm"))

    expect(row.subject).to eq("Confirm")
  end

  it "says how long ago the mail landed" do
    row = Subscriptions::Row.new(build_stubbed(:newsletter, received_at: 4.minutes.ago))

    expect(row.freshness).to eq("4 minutes ago")
  end

  # The original, not the reader: the confirm link is in the sender's own
  # HTML, and the sandboxed frame there is what lets their button work.
  it "points at the sender's own email" do
    newsletter = create(:newsletter)

    row = Subscriptions::Row.new(newsletter)

    expect(row.path).to eq("/newsletters/#{newsletter.id}/original")
  end

  it "draws itself as a linked pen row" do
    row = Subscriptions::Row.new(build_stubbed(:newsletter))

    expect(row.to_partial_path).to eq("subscriptions/row")
  end
end
