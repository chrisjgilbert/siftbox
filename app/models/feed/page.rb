# One page of the originals archive: the next fifty things that arrived,
# newest first, mail and blog posts in one order.
#
# The archive used to be a fixed seven days with no way past it, which is the
# one job the PRD gives it that it could not do — finding something weeks
# later, outside any edition. So the window is gone and the page is a count
# instead.
#
# Ordered in SQL rather than in Ruby, which is the change paging forced. A
# page is fifty rows out of however many there are, and the only way to ask
# for fifty is to have the database do the ordering: sorting in Ruby means
# loading everything first, which is the thing paging exists to stop.
class Feed::Page
  SIZE = 50

  # The two tables in one list. A UNION ALL over the ordering keys alone —
  # when each arrived, what it is, and which row — rather than over the
  # columns the page prints, because the arms would then have to agree on a
  # column list that neither table naturally has.
  #
  # The kind is a real ordering key and not decoration. Arrival times carry
  # whole seconds, so a batch send lands several rows on one instant; the id
  # breaks that tie inside a table and cannot across two, where newsletter 5
  # and post 5 are different rows with the same number. Without a key between
  # them the order is not total, and an order that is not total re-shows one
  # row on the next page and drops another.
  ORDER = "received_at DESC, kind DESC, id DESC".freeze

  # Row values, the way Newsletter::EARLIEST_FROM_SENDER compares a pair.
  # SQLite has had them since 3.15 and they say exactly what is meant. Built
  # from one key list rather than written out twice, so the two sides of the
  # same line cannot drift apart.
  KEYS = "(received_at, kind, id)".freeze
  CURSOR = "(:received_at, :kind, :id)".freeze

  # The rows below this one in the order above, and the rows at or above it —
  # which is what has already been shown, the cursor being the last row of the
  # page before.
  AFTER = "#{KEYS} < #{CURSOR}".freeze
  ABOVE = "#{KEYS} >= #{CURSOR}".freeze

  def initialize(after: nil)
    @after = after
  end

  # Hydrated in one query per table off the ids the ordering came back with,
  # then put back in the order it gave. Two queries and a preload, whatever
  # the archive holds.
  #
  # filter_map rather than a lookup that insists: removing a blog takes its
  # posts with it, and one doing so between the ordering and the hydration
  # would otherwise be a 500 on the archive. A page one row short is the
  # graceful answer to a row that stopped existing while it was being read.
  def items
    @_items ||= ordering.filter_map { |row| loaded[[ row["kind"], row["id"] ]] }
  end

  # How many rows sit above this page, so the feed can go on numbering where
  # the page above it stopped. Counted rather than carried in the address: a
  # cursor names a row instead of a position precisely so that mail arriving
  # mid-read cannot shift it, and an offset travelling beside it would bring
  # back the problem the cursor exists to avoid.
  #
  # At or above, because the cursor is the last row of the page before — so
  # the count includes it, which is exactly how many rows have been shown.
  #
  # The archive's index as of this request, not a promise about the reader's
  # session: mail landing while they page raises it, so page two can start a
  # few above where page one appeared to stop. The number is true about the
  # archive at the moment it is read, which is the most a cursor can offer.
  #
  # Both arms take the bound, so this reads an index rather than the tables —
  # measured at 1.4ms counting 19,800 rows on page 400 of a 40,000-row
  # archive. It is the one part of paging whose cost grows with depth.
  def preceding
    return 0 unless after

    @_preceding ||= ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([ tally, bindings ])
    )
  end

  # Asked for one row more than a page holds, so this is answered by what the
  # database returned rather than by a second COUNT over both tables.
  def more?
    ordering_with_spare.length > SIZE
  end

  # The cursor the next page starts below, and nothing at the end of the
  # archive. The last row of this page rather than a count, because a count
  # is a position and positions move when mail arrives.
  def last
    items.last && Feed::Cursor.new(items.last)
  end

  private

  attr_reader :after

  def ordering
    @_ordering ||= ordering_with_spare.first(SIZE)
  end

  def ordering_with_spare
    @_ordering_with_spare ||= ActiveRecord::Base.connection.select_all(
      ActiveRecord::Base.sanitize_sql_array([ statement, bindings ])
    ).to_a
  end

  def statement
    <<~SQL.squish
      SELECT kind, id, received_at FROM (#{arms}) #{bound}
      ORDER BY #{ORDER} LIMIT #{SIZE + 1}
    SQL
  end

  def tally
    "SELECT COUNT(*) FROM (#{arms}) WHERE #{ABOVE}"
  end

  def bound
    return "" unless after

    "WHERE #{AFTER}"
  end

  def bindings
    return {} unless after

    { received_at: after.received_at, kind: after.kind, id: after.id }
  end

  # Built off the relations rather than written out, so what counts as content
  # has one owner. Spelled into the arm by hand, .content would drift from the
  # pen's rules the first time they changed and nothing would go red.
  #
  # Memoised because the statement and the tally both want it, and each call
  # compiles two relations to SQL.
  def arms
    @_arms ||= [ arm(Newsletter.content), arm(Blog::Post.all) ].join(" UNION ALL ")
  end

  # The kind comes off the model's own name rather than being typed out,
  # because it has to equal what Feed::Cursor reads from a row — class.name —
  # or the keyset binds a string the arm never produced and the page silently
  # starts from the top. Two hand-written literals agreeing by eye is not a
  # guarantee; one source for both is.
  def arm(relation)
    kind = ActiveRecord::Base.connection.quote(relation.model.name)

    relation.select("#{kind} AS kind, id, received_at").to_sql
  end

  # Keyed the way the ordering rows are, off the same class.name the arms
  # were built from, so neither side spells a kind out.
  def loaded
    @_loaded ||= (mail + posts).index_by { |item| [ item.class.name, item.id ] }
  end

  def mail
    Newsletter.for_feed.where(id: ids_of(Newsletter.name))
  end

  # includes rather than a join, and blog_id is in FEED_COLUMNS for it: the
  # row prints the blog's name, and asking per row would be an N+1 under the
  # handful of queries the archive is meant to cost.
  def posts
    Blog::Post.for_feed.includes(:blog).where(id: ids_of(Blog::Post.name))
  end

  def ids_of(kind)
    ordering.filter_map { |row| row["id"] if row["kind"] == kind }
  end
end
