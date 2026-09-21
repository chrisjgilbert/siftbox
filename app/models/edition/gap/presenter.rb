# One line of the editions archive that is a morning without an edition.
#
# The same questions Edition::Presenter answers for a published morning — what
# it is called and what day it covered — so the archive can hold both in one
# list and render each through its own template, the way the Subscriptions
# page holds three kinds of row.
#
# The template is where the two differ: a gap draws no link, because there is
# no edition to open and a row that looked like one and led to a 404 would be
# worse than a row that plainly does not.
class Edition::Gap::Presenter
  delegate :covered_on, to: :gap

  def initialize(gap)
    @gap = gap
  end

  # Stands where the number does. The archive's rows are read down that
  # column, so a morning with no edition has to say so there rather than leave
  # it blank and let the date carry an explanation it cannot give.
  def number
    I18n.t("editions.index.no_edition")
  end

  def date
    I18n.l(gap.covered_on, format: :edition_masthead)
  end

  def to_partial_path
    "editions/gap_row"
  end

  private

  attr_reader :gap
end
