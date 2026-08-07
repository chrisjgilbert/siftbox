class NewslettersController < ApplicationController
  # Destinations a browser only uses for a subresource. Opening a newsletter
  # marks it read, so GET /newsletters/:id writes — and a newsletter can put
  # `<img src="/newsletters/5">` in its own body, which survives both the
  # scrubber and `sanitize` and is stored as lead_image_url, so the feed
  # fetches it for every row with the reader's session attached. The layout's
  # turbo-prefetch meta tag closes one instance of this; Sec-Fetch-Dest closes
  # the class, and leaves Turbo's own visits (dest "empty") and a plain
  # navigation (dest "document") marking read as before.
  SUBRESOURCE_DESTINATIONS = %w[
    audio embed frame iframe image object track video
  ].freeze

  def index
    @feed = Feed.new(filter: params[:filter])
  end

  def show
    newsletter = Newsletter.find(params[:id])
    newsletter.mark_read if reader_opened_it?
    @newsletter = Newsletter::Presenter.new(newsletter)
  end

  private

  def reader_opened_it?
    SUBRESOURCE_DESTINATIONS.exclude?(request.headers["Sec-Fetch-Dest"].to_s)
  end
end
