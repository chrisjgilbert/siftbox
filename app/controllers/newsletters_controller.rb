class NewslettersController < ApplicationController
  def index
    @feed = Feed.new
  end
end
