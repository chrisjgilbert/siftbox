# Serving the images a newsletter or a post carries, from this app rather than
# from Active Storage's own blob routes.
#
# Those routes inherit from ActionController::Base rather than from
# ApplicationController, so they sit outside the authentication gate and their
# signed ids never expire — a permanent public URL for every image in a
# private archive. Serving them here keeps .claude/rules/security.md's "every
# controller authenticates" true, and keeps the paths stable, which expiring
# Active Storage URLs would not: they are written into body_html when the
# images are stored.
#
# Named for what it serves rather than for how the images got here: the two
# controllers hand back images this app stored, whether they arrived inside a
# message as cid: parts or were fetched from a publisher's CDN.
#
# One action shared by the two controllers rather than one controller for
# both, because the routes are nested under different parents. What is shared
# is the part that must not drift: the content type is the sender's or the
# publisher's claim, and rendering whatever they claim, inline and
# same-origin, would hand them this app's origin.
module StoredImages
  extend ActiveSupport::Concern

  def show
    image = record.inline_images.blobs.find(params[:id])
    return head :not_found unless Newsletter::InlineImages.displayable?(image)

    expires_in 1.year, public: false
    send_data image.download, type: image.content_type, disposition: :inline
  end
end
