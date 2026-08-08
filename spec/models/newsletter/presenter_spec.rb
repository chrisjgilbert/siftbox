require "rails_helper"

RSpec.describe Newsletter::Presenter do
  it "shows the sender's display name" do
    newsletter = build_stubbed(:newsletter, sender_name: "Ruby Weekly")

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.sender).to eq("Ruby Weekly")
  end

  # A row headed by a bare em dash reads as a rendering fault.
  it "names an unknown sender when the newsletter carries neither" do
    newsletter = build_stubbed(:newsletter, sender_name: "", sender_email: "")

    expect(Newsletter::Presenter.new(newsletter).sender).to eq("Unknown sender")
  end

  it "has no sender domain when the address is missing" do
    newsletter = build_stubbed(:newsletter, sender_name: "", sender_email: "")

    expect(Newsletter::Presenter.new(newsletter).sender_domain).to be_nil
  end

  it "falls back to the address when the sender has no display name" do
    newsletter = build_stubbed(
      :newsletter,
      sender_name: "",
      sender_email: "peter@rubyweekly.com"
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.sender).to eq("peter@rubyweekly.com")
  end

  it "shows the time of day for a newsletter that arrived today" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-06 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("09:02")
    end
  end

  it "shows the time of day for a newsletter that arrived yesterday" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-05 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("09:02")
    end
  end

  it "shows the weekday for an older newsletter from this week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-08-03 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("Mon")
    end
  end

  it "shows the date for a newsletter older than a week" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-07-28 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("28 Jul")
    end
  end

  it "titles a neighbour with its sender and subject" do
    newsletter = build_stubbed(
      :newsletter,
      sender_name: "Ruby Weekly",
      subject: "Issue 742"
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.title).to eq("Ruby Weekly — Issue 742")
  end

  # `title` is the presenter's own, so this fails if the neighbour comes back
  # unwrapped — which `subject` alone could not tell apart.
  it "wraps the newer neighbour in a presenter" do
    create(:newsletter, received_at: 2.days.ago)
    create(:newsletter, received_at: 1.day.ago, sender_name: "Ruby Weekly",
      subject: "Later one")
    presenter = Newsletter::Presenter.new(Newsletter.order(:received_at).first)

    expect(presenter.newer.title).to eq("Ruby Weekly — Later one")
  end

  it "wraps the older neighbour in a presenter" do
    create(:newsletter, received_at: 2.days.ago, sender_name: "Ruby Weekly",
      subject: "Earlier one")
    create(:newsletter, received_at: 1.day.ago)
    presenter = Newsletter::Presenter.new(Newsletter.order(:received_at).last)

    expect(presenter.older.title).to eq("Ruby Weekly — Earlier one")
  end

  it "has no older neighbour when it is the oldest" do
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(Newsletter::Presenter.new(newsletter).older).to be_nil
  end

  it "shows the date for a newsletter older than the feed's window" do
    travel_to Time.zone.parse("2026-08-06 18:00") do
      newsletter = build_stubbed(
        :newsletter,
        received_at: Time.zone.parse("2026-06-01 09:02")
      )

      expect(Newsletter::Presenter.new(newsletter).timestamp).to eq("1 Jun")
    end
  end

  it "has no newer neighbour when it is the most recent" do
    newsletter = create(:newsletter, received_at: 1.day.ago)

    expect(Newsletter::Presenter.new(newsletter).newer).to be_nil
  end

  it "heads the reader with the sender and the source domain" do
    newsletter = build_stubbed(
      :newsletter,
      sender_name: "This Week in Rails",
      sender_email: "editors@weblog.rubyonrails.org"
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.kicker).to eq("This Week in Rails / weblog.rubyonrails.org")
  end

  it "drops the separator along with a missing domain" do
    newsletter = build_stubbed(:newsletter, sender_name: "Ruby Weekly", sender_email: "")

    expect(Newsletter::Presenter.new(newsletter).kicker).to eq("Ruby Weekly")
  end

  it "stamps the received time for the data strip" do
    newsletter = build_stubbed(
      :newsletter,
      received_at: Time.zone.parse("2026-08-05 09:02")
    )

    presenter = Newsletter::Presenter.new(newsletter)

    expect(presenter.received_line).to eq("Received 2026.08.05 09:02")
  end

  it "shows the issue number when the subject carries one" do
    newsletter = build_stubbed(:newsletter, subject: "#742: A faster CSV parser")

    expect(Newsletter::Presenter.new(newsletter).issue).to eq("Issue 742")
  end

  it "has no issue field when the subject carries no number" do
    newsletter = build_stubbed(:newsletter, subject: "Five articles worth your evening")

    expect(Newsletter::Presenter.new(newsletter).issue).to be_nil
  end

  it "estimates the reading time from the body" do
    body = "<p>#{Array.new(600, 'word').join(' ')}</p>"
    newsletter = build_stubbed(:newsletter, body_html: body)

    expect(Newsletter::Presenter.new(newsletter).reading_time).to eq("3 min")
  end

  # The data strip and the article share one Newsletter::Body, and #body
  # removes the promoted image from the tree the word count then walks. The
  # view renders the strip first, but nothing enforces that, and a reading
  # time that depended on the order would be wrong on whichever render
  # changed it.
  it "estimates the same reading time after the body has been rendered" do
    body = %(<img src="https://cdn.example/hero.png"><p>#{Array.new(600, 'word').join(' ')}</p>)
    newsletter = build_stubbed(:newsletter, body_html: body)
    presenter = Newsletter::Presenter.new(newsletter)
    presenter.body

    expect(presenter.reading_time).to eq("3 min")
  end

  # The reader promotes the first image above the article, so leaving it in
  # the body would show it twice.
  it "leaves the promoted lead image out of the body" do
    newsletter = build_stubbed(
      :newsletter,
      body_html: %(<img src="https://cdn.example/hero.png"><p>Morning</p>)
    )

    expect(Newsletter::Presenter.new(newsletter).body).not_to include("hero.png")
  end

  it "keeps the rest of the body around the promoted image" do
    newsletter = build_stubbed(
      :newsletter,
      body_html: %(<img src="https://cdn.example/hero.png"><p>Morning</p>)
    )

    expect(Newsletter::Presenter.new(newsletter).body).to include("<p>Morning</p>")
  end

  it "captions the promoted image with the email's alt text" do
    newsletter = build_stubbed(
      :newsletter,
      body_html: %(<img src="https://cdn.example/hero.png" alt="The new parser">)
    )

    expect(Newsletter::Presenter.new(newsletter).lead_image_alt).to eq("The new parser")
  end
end
