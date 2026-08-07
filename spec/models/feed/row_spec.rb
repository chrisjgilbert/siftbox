require "rails_helper"

RSpec.describe Feed::Row do
  def row_for(newsletter, position)
    Feed::Row.new(Newsletter::Presenter.new(newsletter), position)
  end

  it "zero-pads the number so the index column stays aligned" do
    row = row_for(build_stubbed(:newsletter), 3)

    expect(row.number).to eq("03")
  end

  it "keeps both digits past nine" do
    row = row_for(build_stubbed(:newsletter), 11)

    expect(row.number).to eq("11")
  end

  # The newest item in the feed is number one, and is by definition in the
  # newest group.
  it "leads the feed when it is first and carries an image" do
    newsletter = build_stubbed(:newsletter, lead_image_url: "https://cdn.example/hero.png")

    row = row_for(newsletter, 1)

    expect(row).to be_lead
  end

  # Full-width treatment with a placeholder where the image should be reads
  # as a broken page, so it falls back to a standard row instead.
  it "does not lead the feed with no image to lead with" do
    row = row_for(build_stubbed(:newsletter, lead_image_url: ""), 1)

    expect(row).not_to be_lead
  end

  it "does not lead the feed from any position but the first" do
    newsletter = build_stubbed(:newsletter, lead_image_url: "https://cdn.example/hero.png")

    row = row_for(newsletter, 2)

    expect(row).not_to be_lead
  end

  it "reads the subject through the presenter" do
    row = row_for(build_stubbed(:newsletter, subject: "Issue 742"), 1)

    expect(row.subject).to eq("Issue 742")
  end

  it "reads the sender through the presenter" do
    row = row_for(build_stubbed(:newsletter, sender_name: "", sender_email: ""), 1)

    expect(row.sender).to eq("Unknown sender")
  end
end
