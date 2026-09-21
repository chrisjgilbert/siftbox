# The index view's collection: one page of the originals archive — mail and
# blog posts alike — grouped by when it arrived, each row already wrapped in
# its presenter.
#
# The page itself is Feed::Page's: what fifty rows are, and how to get the
# fifty below them. What is here is how those rows read — which heading each
# falls under and what it says.
#
# Not scoped to a user. With one inbound address and one account, the
# authentication gate is the scope; a user_id nothing filters on would be
# theatre. See .claude/rules/security.md, and the note in docs/operating.md on
# what multiple users would take.
class Feed
  Group = Struct.new(:label, :sublabel, :items)

  # Today, Yesterday and Earlier, and then months. The named groups cover the
  # week Newsletter::Age knows about; past that a heading reading "Earlier /
  # This week" over mail from June is a heading that lies, and the archive now
  # reaches back that far.
  NAMED = [ :today, :yesterday, :earlier ].freeze

  def initialize(after: nil)
    @page = Feed::Page.new(after: after)
  end

  delegate :more?, :last, to: :page

  # Memoised because the view asks twice: once to render, once to decide
  # between the end-of-list line and the empty state.
  def groups
    @_groups ||= numbered(grouped)
  end

  def item_count
    items.length
  end

  private

  attr_reader :page

  # group_by rather than a range filter per bucket, so the buckets cannot
  # overlap: inclusive ranges that met at midnight put a newsletter into the
  # feed twice.
  #
  # The order falls out rather than being imposed: items arrive newest first
  # and group_by keeps the order it first saw each key in, so the named
  # groups come out in their own order and the months in date order behind
  # them. A fixed list of names could not have named the months anyway.
  def grouped
    items.group_by { |item| bucket_for(item) }.to_a
  end

  # A Date for anything past the named week — the first of the month it
  # arrived in, which is the group's identity and what its heading is drawn
  # from. The year is in there because two Junes are two groups; keyed on the
  # month name alone, a year of archive collapses into twelve headings that
  # each hold several.
  def bucket_for(item)
    bucket = Newsletter::Age.new(item.received_at).bucket
    return item.received_at.to_date.beginning_of_month if bucket == :older

    bucket
  end

  # Rows are numbered continuously across the whole feed rather than
  # restarting per group, so the feed reads as an index. The groups are
  # disjoint and already in order, which makes a running offset enough.
  def numbered(found)
    offset = 0

    found.map do |name, items|
      group(name, items, offset).tap { offset += items.length }
    end
  end

  def group(name, found, offset)
    Group.new(label_for(name), sublabel_for(name), present(found, offset))
  end

  def label_for(name)
    return I18n.l(name, format: :feed_month) unless NAMED.include?(name)

    I18n.t("feed.groups.#{name}")
  end

  # The second line under each heading: the date for the two day groups, the
  # span for Earlier, and the year for a month. Always the year, even in this
  # one, because an archive is read across years and a bare "June" leaves the
  # reader counting back.
  def sublabel_for(name)
    return I18n.l(name, format: :feed_year) unless NAMED.include?(name)
    return I18n.t("feed.groups.this_week") if name == :earlier
    return I18n.l(Date.current, format: :feed_group) if name == :today

    I18n.l(Date.yesterday, format: :feed_group)
  end

  def present(found, offset)
    found.each_with_index.map do |item, index|
      Feed::Row.new(presenter_for(item), offset + index + 1)
    end
  end

  # Each kind answers the same questions about itself, so the row and its
  # template never learn which they are holding.
  def presenter_for(item)
    return Blog::Post::Presenter.new(item) if item.is_a?(Blog::Post)

    Newsletter::Presenter.new(item)
  end

  # Ordered and bounded by Feed::Page, which is where the two tables are put
  # into one list and where the tie-breaks that keep that order total live.
  def items
    @_items ||= page.items
  end
end
