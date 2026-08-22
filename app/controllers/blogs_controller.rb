# The roster of blogs: put one on it, take one off. The list itself is drawn
# by the Subscriptions page, which is where the reader already goes to see
# what reaches them and what does not.
#
# Whether a feed may be followed at all is Blog::Subscription's — it reads the
# feed once and decides, which is a question no controller should be asking a
# publisher's server on its own account.
class BlogsController < ApplicationController
  def create
    blog = Blog.new(blog_params)
    return redirect_to subscriptions_url if Blog::Subscription.new(blog).submit

    @subscriptions = Subscriptions.new(blog: blog)
    render "subscriptions/index", status: :unprocessable_entity
  end

  # Destroyed rather than flagged: the reader is saying this is not a source
  # of theirs, and a row that stays behind is one the hourly poll keeps
  # asking for. The posts go with it in the database, and so do the citations
  # naming them — a published edition loses the sources under its stories,
  # which is the trade of removing a blog rather than muting it. Muting is
  # what the silencing work is for.
  def destroy
    Blog.find(params[:id]).destroy

    redirect_to subscriptions_url
  end

  private

  def blog_params
    params.expect(blog: [ :feed_url ])
  end
end
