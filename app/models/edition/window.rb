# What the next edition covers: everything that became the reader's to read
# since the last edition closed, up to the moment composition starts — the
# mail that arrived, and the blog posts this app first saw.
#
# A high-water mark rather than a fixed 07:00→07:00 range, per the PRD. Under
# fixed ranges a failed run, or mail landing at 07:02, falls into a gap and is
# never covered by anything; under a watermark a missed day leaves no gap
# behind, it makes the next window bigger, and every newsletter belongs to
# exactly one edition.
class Edition::Window
  # How far the first window reaches when there is no edition to take a
  # watermark from. The archive holds weeks of mail from before editions
  # existed, and starting at the beginning of time would put all of it into
  # one prompt — an edition nobody asked for, at several times the token
  # ceiling, discovered as a truncation. Mail older than this belongs to the
  # reader's old inbox and stays in the originals archive; No. 1 covers the
  # same day's worth every edition after it does.
  FIRST_WINDOW = 1.day

  # Takes the closing moment rather than reading the clock, so one reading
  # covers the whole run: the query, the recorded window and the publication
  # time cannot then disagree with each other by the length of a model call.
  def initialize(ended_at)
    @ended_at = ended_at
  end

  attr_reader :ended_at

  def started_at
    @_started_at ||= Edition.watermark || ended_at - FIRST_WINDOW
  end

  # Whole rows, not a column list: Edition::Prompt reads body_html, and
  # Newsletter::FEED_COLUMNS omits it, so one would send the model an
  # edition's worth of subject lines to write from.
  def newsletters
    @_newsletters ||= arrived.or(released).oldest_first.to_a
  end

  # Whole rows again, and for the same reason: the prompt reads body_html and
  # Blog::Post::FEED_COLUMNS omits it.
  #
  # One clause where the mail has two. A post has no confirmation pen to be
  # released out of, so the moment it became the reader's to read and the
  # moment it arrived are the same moment.
  def posts
    @_posts ||= editable(arrived_posts)
  end

  def sources
    Edition::Sources.new(newsletters: newsletters, posts: posts)
  end

  def empty?
    sources.empty?
  end

  # window_started_at and window_ended_at describe the received_at axis only.
  # A newsletter released out of the confirmation pen is cited by the edition
  # whose window it was released into, and its received_at can sit years
  # outside the window recorded here. It looks like a bug and is not one.
  #
  # published_on is the day the reader picks the edition up, dated the way a
  # morning paper is: the window behind it is mostly yesterday's mail. Through
  # the reader's zone rather than the server's, since that is what the
  # masthead prints and what the unique index counts one edition a day by.
  def edition
    Edition.new(
      number: Edition.next_number, published_at: ended_at,
      published_on: ended_at.in_time_zone.to_date, window_started_at: started_at,
      window_ended_at: ended_at
    )
  end

  private

  # includes rather than a join, the way the archive does it: Edition::Prompt
  # quotes each post under its blog's name, so without the preload a window of
  # six posts reads six blogs one at a time.
  def arrived_posts
    Blog::Post
      .where("received_at > :after AND received_at <= :through",
        after: started_at, through: ended_at)
      .includes(:blog).oldest_first.to_a
  end

  # A stub is stored for the archive and kept out of the edition, per
  # Blog::Post::EDITORIAL_MINIMUM.
  #
  # Held back rather than dropped in silence: a post that never reached an
  # edition and a post nobody wrote about look identical from the reader's
  # side, and only one of them is this app's doing.
  def editable(posts)
    enough, thin = posts.partition(&:enough_to_write_from?)
    thin.each { |post| Rails.logger.info(held_back(post)) }

    enough
  end

  def held_back(post)
    "post #{post.id} carries too little to write from; left out of the edition"
  end

  # Half-open, and both ends matter. The previous edition's window is closed
  # at its top, so mail landing on that exact instant belongs to it rather
  # than here; and mail landing while the model is still writing is above this
  # window's top, which is the next edition's watermark, so it is covered
  # tomorrow instead of twice.
  def arrived
    Newsletter.content.where(
      "received_at > :after AND received_at <= :through",
      after: started_at, through: ended_at
    )
  end

  # The second clause, and the one that is easy to leave out. A confirmation
  # sits in the pen for days, so by the time the reader releases it its
  # received_at is well behind the watermark — on arrival alone it would be
  # dropped from this edition and from every edition after it.
  #
  # Through .released as well as the comparison, where the comparison alone
  # would do — a NULL released_at satisfies neither end of it. It is here to
  # name the set this clause is about, so the pen's vocabulary stays owned by
  # Newsletter. It costs nothing in the plan: EXPLAIN QUERY PLAN gives a
  # MULTI-INDEX OR either way, both branches index-served, because SQLite
  # already infers NOT NULL from the comparison and reaches the partial
  # index_newsletters_on_released_at without being told.
  def released
    Newsletter.content.released.where(
      "released_at > :after AND released_at <= :through",
      after: started_at, through: ended_at
    )
  end
end
