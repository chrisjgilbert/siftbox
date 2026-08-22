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
    I18n.l(post.received_at, format: format_for(post.received_at))
  end

  # The blog itself, which is a post's only honest original. A newsletter's
  # original is the mail this app stored; nothing here was ever sent to us.
  def path
    post.url
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

  private

  attr_reader :post

  def format_for(received_at)
    Newsletter::Presenter::TIMESTAMP_FORMATS.fetch(Newsletter::Age.new(received_at).bucket)
  end
end
