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

  private

  def present(edition)
    Edition::Presenter.new(edition)
  end
end
