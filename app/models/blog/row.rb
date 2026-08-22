# One line of the Sources section: what the blog is called, where its feed is
# read from, how it is getting on, and how much of it is stored.
#
# The name comes through the same fallback Blog::Post::Presenter uses, so a
# blog with no title reads here the way its posts read in the archive rather
# than as a blank line.
class Blog::Row
  delegate :feed_url, :to_param, to: :blog

  def initialize(blog)
    @blog = blog
  end

  def name
    blog.title.presence || blog.feed_url
  end

  # The one thing the reader cannot find out any other way. A blog that has
  # stopped being fetchable looks exactly like one that has stopped
  # publishing, and only one of those is worth doing anything about — so a
  # failing blog says how long rather than only that it is.
  def state
    return I18n.t("blogs.state.failing", duration: since(blog.failing_since)) if failing?
    return I18n.t("blogs.state.unpolled") if blog.polled_at.nil?

    I18n.t("blogs.state.polled", duration: since(blog.polled_at))
  end

  def failing?
    blog.failing_since.present?
  end

  def count
    I18n.t("blogs.count", count: blog.posts.size)
  end

  def to_partial_path
    "blogs/row"
  end

  private

  attr_reader :blog

  # The distance rather than the clock time the archive prints, for the reason
  # the pen's rows use it: what the reader needs from this line is how long it
  # has been like that, not the hour it last happened.
  def since(time)
    ActionController::Base.helpers.time_ago_in_words(time)
  end
end
