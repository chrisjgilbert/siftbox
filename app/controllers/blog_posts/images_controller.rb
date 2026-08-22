# Serves the images a blog post hotlinked, once this app has fetched them.
#
# The same reasoning as Newsletters::ImagesController, and the same code
# beside it rather than one controller for both: Active Storage's own blob
# routes inherit from ActionController::Base rather than from
# ApplicationController, so they sit outside the authentication gate and
# their signed ids never expire — a permanent public URL for every image in
# a private archive. Serving them here keeps .claude/rules/security.md's
# "every controller authenticates" true, and keeps the paths stable, which
# expiring Active Storage URLs would not: they are written into body_html
# when the images are stored.
class BlogPosts::ImagesController < ApplicationController
  def show
    image = post.inline_images.blobs.find(params[:id])
    return head :not_found unless Newsletter::InlineImages.displayable?(image)

    expires_in 1.year, public: false
    send_data image.download, type: image.content_type, disposition: :inline
  end

  private

  # Only the id is needed to scope the blob, and a post row carries a body
  # that runs to tens of kilobytes.
  def post
    Blog::Post.select(:id).find(params[:blog_post_id])
  end
end
