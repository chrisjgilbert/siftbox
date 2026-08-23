# Serves the images a blog post hotlinked, once this app has fetched them.
class BlogPosts::ImagesController < ApplicationController
  include StoredImages

  private

  # Only the id is needed to scope the blob, and a post row carries a body
  # that runs to tens of kilobytes.
  def record
    Blog::Post.select(:id).find(params[:blog_post_id])
  end
end
