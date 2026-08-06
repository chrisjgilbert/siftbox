# Serves the images a newsletter carried inside the message.
#
# Active Storage's own blob routes inherit from ActionController::Base, not
# from ApplicationController, so they are not behind the authentication gate
# and their signed ids never expire — a permanent public URL for every image
# in a private archive. Serving them here keeps .claude/rules/security.md's
# "every controller authenticates" true, and keeps the paths stable, which
# expiring Active Storage URLs would not: they are baked into body_html at
# ingest.
class Newsletters::ImagesController < ApplicationController
  # The content type comes from the sender's MIME header. Serving whatever
  # they claim, inline and same-origin, would hand them the app's origin —
  # so only raster images, and never SVG, which can carry script.
  INLINE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  def show
    image = newsletter.inline_images.blobs.find(params[:id])
    return head :not_found unless INLINE_TYPES.include?(image.content_type)

    expires_in 1.year, public: false
    send_data image.download, type: image.content_type, disposition: :inline
  end

  private

  def newsletter
    Newsletter.find(params[:newsletter_id])
  end
end
