# What the next edition covers: every newsletter that became the reader's to
# read since the last edition closed, up to the moment composition starts.
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
  # Newsletter::FEED_COLUMNS and NEIGHBOUR_COLUMNS both omit it, so either
  # would send the model an edition's worth of subject lines to write from.
  def newsletters
    @_newsletters ||= arrived.or(released).oldest_first.to_a
  end

  # Asked before an edition is built, because the PRD skips an empty window
  # silently and Edition::Editor cannot: its completeness check passes
  # vacuously over no newsletters and it would publish an empty edition.
  def empty?
    newsletters.empty?
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
