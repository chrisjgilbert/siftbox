# One line of the Subscriptions page that is a newsletter: who wrote, what
# they called it, how long ago it landed, and the way in to their own HTML.
#
# The sender comes through Newsletter::Presenter rather than off the column,
# so mail with no From header at all reads here the way it reads everywhere
# else instead of as a blank line.
class Subscriptions::Row
  delegate :path, :sender, :subject, to: :presenter

  def initialize(newsletter)
    @newsletter = newsletter
  end

  # "4 minutes ago". The distance rather than the clock time the feed prints,
  # because a confirm link expires within a day or two and how long the row
  # has been sitting there is the thing the reader is judging.
  def freshness
    Newsletter::Age.new(newsletter.received_at).in_words
  end

  def to_partial_path
    "subscriptions/row"
  end

  private

  attr_reader :newsletter

  def presenter
    @_presenter ||= Newsletter::Presenter.new(newsletter)
  end
end
