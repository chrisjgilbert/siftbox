# Display logic for one post, answering everything a feed row asks a
# newsletter's presenter — so the archive draws both from one template rather
# than branching on which it has.
class Blog::Post::Presenter
  delegate :lead_image?, :lead_image_url, :snippet, to: :post

  def initialize(post)
    @post = post
  end

  # The blog's name, falling back to where it is fetched from. A feed that
  # gave no title still has to read as something rather than as a blank.
  def sender
    post.blog.title.presence || post.blog.feed_url
  end

  def subject
    post.title
  end

  def timestamp
    Newsletter::Age.new(post.received_at).timestamp
  end

  # The blog itself, which is a post's only honest original. A newsletter's
  # original is the mail this app stored; nothing here was ever sent to us.
  #
  # A feed item with neither a link nor a permalink guid is stored with no
  # address at all, and an empty href is a link back to the page you are on —
  # so the row would silently reload the archive. The blog is the nearest
  # true answer to "where is this", and where the feed is fetched from is the
  # nearest true answer to that.
  def path
    post.url.presence || post.blog.site_url.presence || post.blog.feed_url
  end

  # A new tab, because the link leaves this app for somebody else's site —
  # and noopener so the page it opens cannot reach back through window.opener,
  # which is the one thing a target of _blank gives away for free.
  def link_attributes
    { target: "_blank", rel: "noopener noreferrer" }
  end

  # The one word that separates a post from a newsletter in the archive. Only
  # posts carry it: they are the rarer thing, so marking them keeps the line
  # quieter than marking the twenty newsletters a day would.
  def kind
    I18n.t("blogs.kind")
  end

  def no_image
    I18n.t("blogs.no_image")
  end

  private

  attr_reader :post
end
