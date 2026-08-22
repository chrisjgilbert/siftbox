# Display logic for one post, answering everything a feed row asks a
# newsletter's presenter — so the archive draws both from one template rather
# than branching on which it has.
class Blog::Post::Presenter
  # The schemes a browser may be sent to. link_to does not filter, and the
  # first two links in #path below are written by the publisher — so without
  # this a feed carrying `<link>javascript:…</link>` becomes an href the
  # reader's own click executes, on this app's origin. The CSP blocks it in a
  # current browser, and the CSP describes itself as the second line; on this
  # path it would be the only one.
  #
  # Protocol-relative is kept, as it is for images in
  # Newsletter::LeadImage::HOSTED_SCHEMES: plenty of feeds still write them,
  # and they resolve to the publisher's own host the same as https.
  FOLLOWABLE_SCHEMES = %w[http:// https:// //].freeze

  delegate :lead_image?, :lead_image_url, :snippet, to: :post

  def initialize(post)
    @post = post
  end

  def sender
    post.blog.name
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
    followable(post.url) || followable(post.blog.site_url) || post.blog.feed_url
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

  # The feed_url this chain ends at is the reader's own and is validated for
  # scheme on Blog, so the chain always ends somewhere a browser can go.
  def followable(url)
    return if url.blank?
    return unless url.start_with?(*FOLLOWABLE_SCHEMES)

    url
  end
end
