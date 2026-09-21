# Muting a blog, and the way back. The other half of removing one: destroy
# takes the posts and the citations naming them, this takes nothing.
#
# A muted blog is still polled and still stores what it publishes, so the
# originals archive keeps filling and unmuting has something behind it. What
# stops is the blog reaching an edition.
class Blogs::SilencesController < ApplicationController
  def create
    blog.silence

    redirect_to subscriptions_url
  end

  def destroy
    blog.unsilence

    redirect_to subscriptions_url
  end

  private

  def blog
    @_blog ||= Blog.find(params[:blog_id])
  end
end
