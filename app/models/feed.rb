# The index view's collection: newsletters from the last week, grouped by the
# day they arrived, each row already wrapped in its presenter.
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
    buckets.filter_map do |name, found|
      next if found.empty?

      Group.new(label_for(name), sublabel_for(name), present(found))
    end
  end

  def unread_count
    within_window.unread.count
  end

  private

  attr_reader :filter

  # group_by rather than three range filters, so the buckets cannot overlap:
  # an inclusive range ending where the next one begins put a newsletter that
  # arrived at exactly midnight into the feed twice.
  def buckets
    grouped = newsletters.group_by { |newsletter| bucket_for(newsletter.received_at) }

    [ :today, :yesterday, :earlier ].map { |name| [ name, grouped.fetch(name, []) ] }
  end

  # Open at the top. received_at comes from the sender's Date header, so a
  # skewed clock or a scheduled send can date a newsletter in the future;
  # bounding this at end of day left it counted as unread but in no group,
  # and so unreachable.
  def bucket_for(received_at)
    return :today if received_at >= Date.current.beginning_of_day
    return :yesterday if received_at >= Date.yesterday.beginning_of_day

    :earlier
  end

  def label_for(name)
    I18n.t("feed.groups.#{name}")
  end

  def sublabel_for(name)
    return I18n.t("feed.groups.this_week") if name == :earlier
    return I18n.l(Date.current, format: :feed_group) if name == :today

    I18n.l(Date.yesterday, format: :feed_group)
  end

  def present(found)
    found.map { |newsletter| Newsletter::Presenter.new(newsletter) }
  end

  # Loaded once and partitioned in Ruby: three date groups off one query.
  def newsletters
    @_newsletters ||= filtered.for_feed.newest_first.to_a
  end

  def filtered
    return within_window.unread if filter == "unread"

    within_window
  end

  def within_window
    Newsletter.where(received_at: WINDOW.ago..)
  end
end
