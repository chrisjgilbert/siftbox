# The pen and the two nets around it: what is waiting to be confirmed, who has
# written for the first time, and what the spam gate refused. An index and
# nothing else — resolving a hold is a nested resource of its own.
class SubscriptionsController < ApplicationController
  def index
    @subscriptions = Subscriptions.new(blog: Blog.new(feed_url: offered))
  end

  private

  # The page a bookmarklet was fired from. It need not be a feed:
  # Blog::Subscription reads a page for the one it announces, which is how
  # readers know their blogs.
  #
  # Held to the format the column is held to, because this is reflected into
  # a field the reader is looking at. ERB escapes it either way — what this
  # stops is the field offering them a string that is not an address at all.
  def offered
    address = params[:feed_url].to_s

    return "" unless address.match?(Blog::FETCHABLE)

    address
  end
end
