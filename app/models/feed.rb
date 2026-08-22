# The index view's collection: everything from the last week — mail and blog
# posts alike — grouped by the day it arrived, each row already wrapped in its
# presenter.
#
# Not scoped to a user. With one inbound address and one account, the
# authentication gate is the scope; a user_id nothing filters on would be
# theatre. See .claude/rules/security.md, and the note in README.md on what
# multiple users would take.
class Feed
  Group = Struct.new(:label, :sublabel, :items)

  # Memoised because the view asks twice: once to render, once to decide
  # between the end-of-list line and the empty state.
  def groups
    @_groups ||= numbered(grouped)
  end

  def item_count
    items.length
  end

  private

  # group_by rather than a range filter per bucket, so the buckets cannot
  # overlap: inclusive ranges that met at midnight put a newsletter into the
  # feed twice.
  def grouped
    found = items.group_by { |item| bucket_for(item) }

    [ :today, :yesterday, :earlier ].filter_map { |name| [ name, found[name] ] if found[name] }
  end

  # Everything the query returned is inside the window by definition. A row
  # can still bucket :older, because Age reads the clock again a moment after
  # the query did, and the filter_map above would then drop it from the page
  # while #item_count still counts it — an end-of-feed line claiming more
  # items than it shows, or an empty state with a row behind it.
  def bucket_for(item)
    bucket = Newsletter::Age.new(item.received_at).bucket
    return :earlier if bucket == :older

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
    I18n.t("feed.groups.#{name}")
  end

  def sublabel_for(name)
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

  # Loaded once and partitioned in Ruby: three date groups off two queries.
  #
  # Merged and sorted here rather than in SQL because the page already holds
  # its whole window in memory to group it by day, and a UNION over two tables
  # with different columns would buy nothing back.
  #
  # The order is over three keys, and the third is the one that is easy to
  # miss. Every ordering in this app breaks ties on the id, because arrival
  # times carry whole seconds and a batch send lands on one instant — but that
  # stops being a total order across two tables, where newsletter 5 and post 5
  # are not comparable. Without the class name between them, tied rows swap
  # places between page loads and the continuous numbering swaps with them.
  def items
    @_items ||= (mail + posts).sort_by { |item| ordering(item) }.reverse
  end

  def ordering(item)
    [ item.received_at, item.class.name, item.id ]
  end

  def mail
    within_window.for_feed.to_a
  end

  # includes rather than a join, and blog_id is in FEED_COLUMNS for it: the
  # row prints the blog's name, and asking per row would be an N+1 under the
  # one query the archive is meant to cost.
  def posts
    Blog::Post.where(received_at: Newsletter::Age::WINDOW.ago..)
      .for_feed.includes(:blog).to_a
  end

  # .content, not a bare Newsletter: a subscription confirmation sitting in
  # the pen, or dismissed out of it, is administrative mail and answering
  # "did Money Stuff arrive?" with a Substack confirmation defeats the point
  # of the archive. Applied here rather than left to each caller, because
  # nothing goes red when it is forgotten — the archive just quietly grows
  # mail the reader has already dealt with.
  def within_window
    Newsletter.content.where(received_at: Newsletter::Age::WINDOW.ago..)
  end
end
