require "rails_helper"

# The whole chain, with nothing faked but the sender's CDN: a newsletter
# arrives hotlinking an image, the queued job fetches it, and the reader
# loads it back from this app. Every other spec for these classes injects
# one side of that, so this is what proves the wiring.
RSpec.describe "Newsletter ingest" do
  include ActiveJob::TestHelper

  def ingest(html)
    # TEST-NET-3, so a miss cannot become a real connection. Stubbed because
    # WebMock blocks HTTP but not the name lookup that precedes it.
    allow(Resolv).to receive(:getaddresses).and_return([ "203.0.113.9" ])
    stub_request(:get, "https://cdn.example.com/hero.png")
      .to_return(body: "png-bytes", headers: { "Content-Type" => "image/png" })

    perform_enqueued_jobs { Newsletter::InboundMessage.new(mail: mail_with(html)).save }
  end

  def mail_with(html)
    Mail.new(from: "peter@rubyweekly.com", subject: "Issue 742") do
      html_part do
        content_type "text/html; charset=UTF-8"
        body html
      end
    end
  end

  it "serves a hotlinked image from this app once ingest has run" do
    sign_in
    newsletter = ingest(%(<img src="https://cdn.example.com/hero.png">))

    get newsletter_image_path(newsletter, newsletter.inline_images.blobs.first)

    expect(response.body).to eq("png-bytes")
  end

  it "points the stored body at the image this app serves" do
    newsletter = ingest(%(<img src="https://cdn.example.com/hero.png">))

    expect(newsletter.reload.body_html).to include(
      newsletter_image_path(newsletter, newsletter.inline_images.blobs.first)
    )
  end

  it "leaves no reference to the sender's image host behind" do
    newsletter = ingest(%(<img src="https://cdn.example.com/hero.png">))

    expect(newsletter.reload.body_html).not_to include("cdn.example.com")
  end
end
