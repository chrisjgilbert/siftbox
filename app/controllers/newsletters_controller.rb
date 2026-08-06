class NewslettersController < ApplicationController
  def index
    @feed = Feed.new(filter: params[:filter])
  end

  def show
    newsletter = Newsletter.find(params[:id])
    newsletter.mark_read
    @newsletter = Newsletter::Presenter.new(newsletter)
  end
end
