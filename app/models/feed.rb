# The index view's collection: newsletters from the last week, grouped by the
# day they arrived, each row already wrapped in its presenter.
#
# Not scoped to a user. With one inbound address and one account, the
# authentication gate is the scope; a user_id nothing filters on would be
# theatre. See .claude/rules/security.md, and the note in README.md on what
# multiple users would take.
class Feed
  UNREAD = "unread".freeze

  Group = Struct.new(:label, :sublabel, :newsletters)

  def initialize(filter: nil)
    @filter = filter
  end

  # Memoised because the view asks twice: once to render, once to decide
  # between the end-of-list line and the empty state.
  def groups
    @_groups ||= numbered(grouped)
  end

  def issue_count
    newsletters.length
  end

  def unread_count
    within_window.unread.count
  end

  def unread_only?
    filter == UNREAD
  end

  def everything?
    !unread_only?
  end

  private

  attr_reader :filter

  # group_by rather than a range filter per bucket, so the buckets cannot
  # overlap: inclusive ranges that met at midnight put a newsletter into the
  # feed twice.
  def grouped
    found = newsletters.group_by { |newsletter| Newsletter::Age.new(newsletter.received_at).bucket }

    [ :today, :yesterday, :earlier ].filter_map { |name| [ name, found[name] ] if found[name] }
  end

  # Rows are numbered continuously across the whole feed rather than
  # restarting per group, so the feed reads as an index. The groups are
  # disjoint and already in order, which makes a running offset enough.
  def numbered(found)
    offset = 0

    found.map do |name, newsletters|
      group(name, newsletters, offset).tap { offset += newsletters.length }
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
    found.each_with_index.map do |newsletter, index|
      Feed::Row.new(Newsletter::Presenter.new(newsletter), offset + index + 1)
    end
  end

  # Loaded once and partitioned in Ruby: three date groups off one query.
  def newsletters
    @_newsletters ||= filtered.for_feed.newest_first.to_a
  end

  def filtered
    return within_window.unread if unread_only?

    within_window
  end

  def within_window
    Newsletter.where(received_at: Newsletter::Age::WINDOW.ago..)
  end
end
