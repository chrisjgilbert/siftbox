class NewslettersController < ApplicationController
  def index
    @feed = Feed.new(filter: params[:filter])
  end
end
