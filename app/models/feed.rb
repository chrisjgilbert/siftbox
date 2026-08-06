# The index view's collection: newsletters from the last week, grouped by the
# day they arrived.
#
# Not scoped to a user. With one inbound address and one account, the
# authentication gate is the scope; a user_id nothing filters on would be
# theatre. See .claude/rules/security.md, and the note in README.md on what
# multiple users would take.
class Feed
  WINDOW = 7.days

  Group = Struct.new(:label, :sublabel, :newsletters)

  def initialize(filter: nil)
    @filter = filter
  end

  def groups
    [ today, yesterday, earlier ].compact
  end

  def unread_count
    within_window.unread.count
  end

  private

  attr_reader :filter

  def today
    group("today", Date.current.all_day, I18n.l(Date.current, format: :feed_group))
  end

  def yesterday
    group("yesterday", Date.yesterday.all_day,
      I18n.l(Date.yesterday, format: :feed_group))
  end

  def earlier
    group("earlier", WINDOW.ago..Date.yesterday.beginning_of_day,
      I18n.t("feed.groups.this_week"))
  end

  def group(name, range, sublabel)
    found = newsletters.select { |newsletter| range.cover?(newsletter.received_at) }
    return if found.empty?

    Group.new(I18n.t("feed.groups.#{name}"), sublabel, found)
  end

  # Loaded once and partitioned in Ruby: three date groups off one query.
  def newsletters
    @_newsletters ||= filtered.newest_first.to_a
  end

  def filtered
    return within_window.unread if filter == "unread"

    within_window
  end

  def within_window
    Newsletter.where(received_at: WINDOW.ago..)
  end
end
