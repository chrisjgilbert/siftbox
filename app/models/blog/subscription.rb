# The reader following a blog: read what they pasted, decide whether it is a
# feed this app reads at all, and put it on the roster if it is.
#
# What they pasted may be the blog's home page rather than its feed — which is
# how readers know their blogs, since most sites never show a feed address.
# So a document that is not a feed is read once for the feed it announces, and
# that is fetched instead.
#
# A domain object rather than a validation on Blog, because deciding this
# means asking the publisher's server — and a validation that fetches would
# fire on every poll's own update! as well as here. Blog carries what is true
# of a row; this carries what is true of adding one.
#
# Errors land on the blog rather than here, so the form the reader is looking
# at draws them without a second object to ask.
class Blog::Subscription
  # How much of a feed has to read like writing before this app will take it.
  #
  # A majority, and the numbers it separates are miles apart: the two
  # aggregator feeds measured for docs/blogs-rss.md have a median body of
  # eight characters — a Hacker News item's whole body is the word "Comments",
  # because its description is a link back to its own thread — where 9 of the
  # 273 in-scope items came in under four hundred. So a blog that publishes
  # the odd stub is nowhere near this, and an aggregator is nowhere near it
  # from the other side.
  #
  # Refused while the reader is standing there rather than quietly dropped
  # later, which is the only moment there is to say why: an aggregator's
  # forty items a day would otherwise reach Edition::Prompt as forty sources,
  # each of which the instructions require a story to cite, write only from,
  # and invent nothing into — from a headline and the word "Comments".
  READABLE_SHARE = 0.5

  FETCH = ->(blog) { Blog::Fetch.new(blog).result }

  def initialize(blog, fetch: FETCH)
    @blog = blog
    @fetch = fetch
  end

  def submit
    return false unless blog.valid?
    return false unless readable?

    follow
  end

  private

  attr_reader :blog, :fetch

  # The sample is the first poll rather than a second request. The reader is
  # waiting, the document has just been read, and polling again would ask the
  # publisher for the same bytes twice — so Blog::Poll is handed what is
  # already in hand, through the seam it takes for exactly this.
  def follow
    blog.save!
    Blog::Poll.new(blog, fetch: ->(_blog) { fetched }).save
    true
  end

  def readable?
    announced if posts.nil?

    return refuse(:unreachable) if fetched.nil?
    return refuse(:unreadable) if posts.nil?
    return refuse(:empty) if posts.empty?
    return refuse(:aggregator) if stubs?

    true
  end

  # What the reader pasted was a home page rather than a feed, which is how
  # readers know their blogs: most of them never show a feed address at all.
  # So the page is read for the one it announces and that is fetched instead.
  #
  # Once, and only from a document that was not a feed. A page announcing
  # itself, or two announcing each other, would otherwise walk until something
  # else stopped it — and the second fetch goes through Download the same as
  # the first, so a discovered address gets every refusal the pasted one got.
  def announced
    address = Blog::FeedLink.new(fetched&.document, blog.feed_url).url
    return if address.nil?

    blog.feed_url = address
    reread
  end

  # Assigned rather than re-memoised, so there is one place either of these is
  # read from and no window where the two disagree about which fetch they came
  # from.
  def reread
    @_fetched = fetch.call(blog)
    @_posts = read
  end

  def refuse(reason)
    blog.errors.add(:feed_url, reason)
    false
  end

  # Measured on the prose the editor would be shown rather than on the markup,
  # through the same reading Blog::Post's own floor uses — so a feed admitted
  # here and a post kept out of an edition cannot disagree about what a body
  # is worth.
  def stubs?
    readable = posts.count { |post| Newsletter::Body.prose(post.body_html).length >= floor }

    readable < posts.length * READABLE_SHARE
  end

  def floor
    Blog::Post::EDITORIAL_MINIMUM
  end

  # Nothing rather than an empty list when the document is not a feed, so the
  # two refusals stay different sentences: a parked domain and a blog between
  # posts are not the same thing to tell the reader.
  def posts
    @_posts = read unless defined?(@_posts)

    @_posts
  end

  def read
    return if fetched.nil?

    Blog::Feed.new(fetched.document).posts
  rescue Blog::Feed::Malformed
    nil
  end

  # UNCHANGED cannot arrive: a blog being added has no validators to send, so
  # nothing asks the server a question it could answer 304 to.
  def fetched
    return @_fetched if defined?(@_fetched)

    @_fetched = fetch.call(blog)
  end
end
