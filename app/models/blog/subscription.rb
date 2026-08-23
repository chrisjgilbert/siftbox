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

  # How many of a feed's items are read to decide what kind of feed it is.
  #
  # A feed's character shows in its first items: an aggregator's are uniformly
  # stubs and a blog's are uniformly not, so twenty is ample for a question
  # that is answered by a majority. Reading all of them told us nothing more
  # and cost ten seconds of the twenty-one a real blog's first subscription
  # took — every item's HTML parsed to judge a feed nobody had asked us to
  # judge item by item.
  SAMPLE = 20

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

  attr_reader :blog, :fetch, :fetched, :posts, :refusal

  # The row is written and the reading is asked for, not done. The sample
  # above is what the reader is waiting on and it is bounded; storing a back
  # catalogue is not — a real blog's took twenty seconds inside the request,
  # on one of the three threads the whole app has, with a row and an
  # image-fetching job per item inside a single SQLite write transaction.
  #
  # It costs one more fetch, of a document already read once. That is the
  # trade: the reader is told yes or no in about a second, the roster row is
  # there when they land back on the page, and it fills in behind them.
  def follow
    blog.save!
    Blog::PollJob.perform_later(blog)
    true
  end

  def readable?
    reread
    announced if posts.nil?

    return true if refusal.nil?

    refuse(refusal)
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
    blog.feed_url = pasted if refusal
  end

  # Everything this decides about a feed comes out of one fetch and is
  # assigned together, so a discovery hop cannot leave the document, the items
  # read out of it and the verdict on them describing different fetches.
  #
  # The verdict is assigned rather than asked for twice: reaching it reads
  # twenty bodies through Newsletter::Prose, and the home-page path asks once
  # to decide whether the announced feed was worth swapping to and again to
  # decide whether to take it.
  #
  # Blog::Fetch::UNCHANGED cannot arrive here: a blog being added has no
  # validators to send, so nothing asks the server a question it could answer
  # 304 to. #read would have no document to take from one if it did.
  def reread
    @fetched = fetch.call(blog)
    @posts = read
    @refusal = fault
  end

  # The one statement of what this app will not take, so what turns away a
  # pasted feed and what decides an announced one was not worth swapping to
  # cannot drift apart.
  #
  # Ordered so the reader is told the first thing that is wrong. A parked
  # domain, a page that is not a feed, a blog between posts and an aggregator
  # are four different sentences — nothing rather than an empty list when the
  # document is not a feed is what keeps the middle two apart.
  def fault
    return :unreachable if fetched.nil?
    return :unreadable if posts.nil?
    return :empty if posts.empty?
    return :aggregator if stubs?

    nil
  end

  def refuse(reason)
    blog.errors.add(:feed_url, reason)
    false
  end

  # Measured on the prose the editor would be shown rather than on the markup,
  # so a feed that is mostly markup is judged on what is left of it.
  def stubs?
    sample = posts.first(SAMPLE)
    writing = sample.count { |post| Newsletter::Body.prose(post.body_html).length >= STUB_LENGTH }

    writing < sample.length * READABLE_SHARE
  end

  def read
    return if fetched.nil?

    Blog::Feed.new(fetched.document).posts
  rescue Blog::Feed::Malformed
    nil
  end
end
