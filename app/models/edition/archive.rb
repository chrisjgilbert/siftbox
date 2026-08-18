# The index view's collection: every edition there has ever been, newest
# first, each one wrapped in its presenter.
#
# Newest by the day covered rather than by number. The two agree in normal
# operation; under a manual backfill an edition composed late takes the higher
# number and files under the earlier day, so the archive reads No. 1, No. 3,
# No. 2. That is the archive telling the truth about when the day happened.
#
# Unpaginated, against .claude/rules/database.md. One edition a day is a page
# of 365 lines a year against a table nothing else scrolls, and an archive
# that hides the oldest editions behind a link is the one thing an archive
# must not do. Revisit when it is long enough to notice.
class Edition::Archive
  def editions
    @_editions ||= Edition.for_archive.newest_first.map { |edition| present(edition) }
  end

  def any?
    editions.any?
  end

  # Counted off the editions already loaded rather than asked of the table
  # again, the way Feed#issue_count is, so the figure at the head of the list
  # cannot disagree with the list under it.
  def count
    editions.length
  end

  private

  def present(edition)
    Edition::Presenter.new(edition)
  end
end
