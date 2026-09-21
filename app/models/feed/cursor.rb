# Where the reader got to in the archive: the last row of the page they are
# looking at, and so the top bound of the next one.
#
# Three parts, because that is what the feed's order is: arrival time, then
# the kind, then the id. The kind is in there because the order runs across
# two tables and a batch send lands several rows on one instant — newsletter 5
# and post 5 are not comparable, so without it tied rows swap places between
# page loads and a reader paging back sees one twice and another not at all.
# Feed::Page::ORDER sorts on the same three keys for the same reason, and its
# specs page through a batch that landed on one instant to prove it.
#
# An offset would have been simpler and is wrong here: mail arriving while the
# reader is paging shifts every row down by one, so page two re-shows the
# bottom of page one. A cursor names a row rather than a position, so what
# arrives above it changes nothing.
class Feed::Cursor
  # The kinds the archive holds, and the whole of what a parameter may name.
  # The kind is a class this app then loads from, so left to the parameter it
  # would be an instruction to constantize whatever a stranger put in a URL.
  KINDS = { "Newsletter" => Newsletter, "Blog::Post" => Blog::Post }.freeze

  attr_reader :id, :kind, :received_at

  # Nothing rather than a raise for anything that does not name a row the
  # archive holds: a cursor is a position in a list, and the honest answer for
  # a position that is not there is the first page. A 404 on an archive the
  # reader reached from their own history would be worse, and a page bounded
  # by a row that has gone would be worse still.
  def self.naming(kind, id)
    model = KINDS[kind.to_s]
    return unless model && id.to_s.match?(/\A\d+\z/)

    # The two ordering keys it does not already have, and nothing else. Read
    # whole, this loads a body_html running to hundreds of kilobytes on every
    # paged request — the same discipline Newsletter::FEED_COLUMNS keeps for
    # the rows the page actually prints.
    row = model.select(:id, :received_at).find_by(id: id)
    return unless row

    new(row)
  end

  def initialize(row)
    @kind = row.class.name
    @id = row.id
    @received_at = row.received_at
  end

  # Two plain parameters rather than one encoded string, so the address says
  # what it means and nothing has to be parsed back out of it.
  def to_query
    { after_kind: kind, after_id: id }
  end
end
