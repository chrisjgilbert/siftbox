# The index view's collection: every morning that has something to say for
# itself, newest first — the editions there have ever been, and the mornings
# composition failed on.
#
# The failures are here on purpose and stay here. An edition missing from the
# archive with nothing in its place is indistinguishable from a morning nothing
# arrived on, and the reader has no way to tell which they are looking at. A
# row that says so is the whole of the honesty this page can offer.
#
# Mornings that were merely empty are left out: nothing arrived, which needs no
# explanation, and a list of quiet days is not an archive of anything.
#
# Newest by the day covered rather than by number. The two agree in normal
# operation; under a manual backfill an edition composed late takes the higher
# number and files under the earlier day, so the archive reads No. 1, No. 3,
# No. 2. That is the archive telling the truth about when the day happened.
#
# Unpaginated, against .claude/rules/database.md. One row a day is a page of
# 365 lines a year against tables nothing else scrolls, and an archive that
# hides the oldest editions behind a link is the one thing an archive must not
# do. Revisit when it is long enough to notice.
class Edition::Archive
  # Editions and failures merged into one list, sorted by the day each
  # covered. Two queries rather than a union: they are different tables
  # holding different things, and the page wants a dozen rows of each at most.
  #
  # A morning composed again by hand after an outage has both a gap and an
  # edition. The edition wins: the failure is history by then, and a list
  # carrying "No edition" beside the edition for the same day contradicts
  # itself on one line.
  def rows
    @_rows ||= (published + unresolved).sort_by(&:covered_on).reverse
  end

  def any?
    rows.any?
  end

  # The editions, not the rows. The caption this figure sits in says how many
  # editions there are, and a failure is a row without one — counting it would
  # have the page claim an edition the reader cannot open.
  #
  # Counted off the editions already loaded rather than asked of the table
  # again, the way Feed#issue_count is, so the figure at the head of the list
  # cannot disagree with the list under it.
  def count
    published.length
  end

  private

  # Memoised because #unresolved asks for it again, to find which mornings
  # already have an edition.
  def published
    @_published ||=
      Edition.for_archive.newest_first.map { |edition| Edition::Presenter.new(edition) }
  end

  # Sifted in Ruby off the editions already loaded rather than asked for with
  # a NOT IN: both sets are a page long, and the days are in hand.
  def unresolved
    composed = published.map(&:covered_on)

    Edition::Gap.failed_first
      .reject { |gap| composed.include?(gap.covered_on) }
      .map { |gap| Edition::Gap::Presenter.new(gap) }
  end
end
