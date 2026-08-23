# Serves the images a newsletter carried inside the message.
class Newsletters::ImagesController < ApplicationController
  include StoredImages

  private

  # Only the id is needed to scope the blob, and a newsletter row carries a
  # body that runs to hundreds of kilobytes.
  def record
    Newsletter.select(:id).find(params[:newsletter_id])
  end
end
