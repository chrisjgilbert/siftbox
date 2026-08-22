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
  # Below this, an item's body is a pointer rather than a piece of writing.
  #
  # Its own number rather than Blog::Post::EDITORIAL_MINIMUM, which answers a
  # different question — is there enough in this one post to write a story
  # from — and answers it four times higher. Borrowing it turned away a whole
  # documented class of legitimate blog: WordPress's Excerpt setting publishes
  # 55 words, which reads through Newsletter::Prose at about 330 characters,
  # and docs/blogs-rss.md is explicit that a feed carrying two lines and a
  # "read more" link is in scope.
  #
  # A hundred, because what the measurement actually found is that an
  # aggregator item's whole body is a link back to its own thread — and
  # Newsletter::Prose strips URLs, so what is left is the word "Comments".
  # Eight characters against three hundred and thirty, with this between them.
  STUB_LENGTH = 100

  # How much of a feed has to read like writing before this app will take it.
  # At least half, so one stub in a real blog's feed costs it nothing and one
  # long self-post in an aggregator's buys it nothing.
  #
  # Refused while the reader is standing there rather than quietly dropped
  # later, which is the only moment there is to say why: an aggregator's forty
  # items a day would otherwise reach Edition::Prompt as forty sources, each
  # of which the instructions require a story to cite, write only from, and
  # invent nothing into — from a headline and the word "Comments".
  #
  # It catches Hacker News and lobste.rs, which is what it was measured
  # against. It does not catch a Planet-style rollup that syndicates whole
  # posts: that reads exactly like a blog, because as far as this test is
  # concerned it is one. Out of scope in docs/blogs-rss.md, unenforced here.
  READABLE_SHARE = 0.5

  def initialize(blog, fetch: Blog::Fetch::DEFAULT)
    @blog = blog
    @fetch = fetch
  end

  def submit
    return false unless blog.valid?
    return false unless readable?
    return false unless blog.valid?

    follow
  end

  private

  attr_reader :blog, :fetch

  # The sample is the first poll rather than a second request. The reader is
  # waiting, the document has just been read, and polling again would ask the
  # publisher for the same bytes twice — so Blog::Poll is handed what is
  # already in hand, through the seam it takes for exactly this.
  #
  # One transaction over the two, so a poll that raises leaves no blog behind.
  # Without it the row survived with nothing in it, reading "Not checked yet"
  # on the roster while the reader saw an error page and a retry earned "has
  # already been taken". The reason Blog::Poll keeps its own fetch outside a
  # transaction does not apply: the document is already in hand and nothing
  # here touches the network.
  def follow
    blog.transaction do
      blog.save!
      Blog::Poll.new(blog, fetch: ->(_blog) { fetched }).save
    end

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
  # The pasted address is put back before returning, whatever the outcome. It
  # is what the form redisplays, and a reader refused over a feed they never
  # typed gets advice about a page they never saw. Only #follow keeps the
  # discovered one, and only once it has been accepted.
  def announced
    pasted = blog.feed_url
    address = Blog::FeedLink.new(fetched&.document, pasted).url
    return if address.nil?

    blog.feed_url = address
    reread
    blog.feed_url = pasted unless readable_now?
  end

  # Asked before the refusals are recorded, so the address goes back without
  # this having decided anything: #readable? is what decides, and it runs
  # again the moment #announced returns.
  def readable_now?
    posts.present? && !stubs?
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
  # so a feed that is mostly markup is judged on what is left of it.
  def stubs?
    writing = posts.count { |post| Newsletter::Body.prose(post.body_html).length >= STUB_LENGTH }

    writing < posts.length * READABLE_SHARE
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
