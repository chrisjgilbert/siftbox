# One line of the Sources section: what the blog is called, where its feed is
# read from, how it is getting on, and how much of it is stored.
#
# The name is the blog's own, so a blog with no title reads here the way its
# posts read in the archive rather than as a blank line.
class Blog::Row
  include ActionView::Helpers::DateHelper

  delegate :feed_url, :name, :silenced?, :to_param, to: :blog

  # The count is handed over rather than asked for: the page draws the whole
  # roster, and a row that counted its own posts would be one query each.
  def initialize(blog, stored)
    @blog = blog
    @stored = stored
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
    I18n.t("blogs.count", count: stored)
  end

  # The class the whole state line takes, rather than a conditional the
  # template assembles: the sibling section documents that move — the name
  # goes on the element and the CSS hangs off it, so no template asks which
  # thing it is drawing.
  def state_class
    return "sources__state sources__state--failing" if failing?

    "sources__state"
  end

  # A blog with no title is named by its feed address, so printing the address
  # underneath prints it twice — at 390px that is one row twice as tall as its
  # neighbours saying one thing.
  def feed?
    name != feed_url
  end

  def to_partial_path
    "blogs/row"
  end

  private

  attr_reader :blog, :stored

  # The distance rather than the clock time the archive prints, for the reason
  # the pen's rows use it: what the reader needs from this line is how long it
  # has been like that, not the hour it last happened.
  #
  # Through the helper module the way Newsletter::Age reads its own distance,
  # rather than through ActionController::Base.helpers: a row on a page is not
  # a reason to build a view context, and the two lines print the same thing.
  def since(time)
    time_ago_in_words(time)
  end
end
