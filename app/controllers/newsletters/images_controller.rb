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
  def show
    image = newsletter.inline_images.blobs.find(params[:id])
    return head :not_found unless Newsletter::InlineImages.displayable?(image)

    expires_in 1.year, public: false
    send_data image.download, type: image.content_type, disposition: :inline
  end

  private

  # Only the id is needed to scope the blob, and a newsletter row carries a
  # body that runs to hundreds of kilobytes.
  def newsletter
    Newsletter.select(:id).find(params[:newsletter_id])
  end
end
