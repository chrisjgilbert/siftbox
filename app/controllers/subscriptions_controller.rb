# The pen and the two nets around it: what is waiting to be confirmed, who has
# written for the first time, and what the spam gate refused. An index and
# nothing else — resolving a hold is a nested resource of its own.
class SubscriptionsController < ApplicationController
  # The blog carries whatever a bookmarklet handed over: the page the reader
  # was standing on, which need not be a feed, since Blog::Subscription reads
  # a page for the one it announces.
  #
  # Filled into the form and never followed. A create on a GET would put a
  # blog on the roster for any page that embedded the URL, and would sit
  # outside the resourceful route that owns it.
  def index
    @subscriptions = Subscriptions.new(blog: Blog.offered(params[:feed_url]))
  end
end
