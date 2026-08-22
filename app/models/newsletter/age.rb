# How long ago a newsletter arrived, as the feed thinks about it.
#
# One owner for the day boundaries, and for the clock face that goes with
# each: a row can never be formatted by one rule and filed under a heading
# decided by another, because the same object answers both questions. The
# format table lived on Newsletter::Presenter until a second presenter had to
# reach across for it.
class Newsletter::Age
  include ActionView::Helpers::DateHelper

  WINDOW = 7.days

  # Which clock face each bucket gets. Today and yesterday print the hour,
  # because that is what tells two of the day's rows apart; older than that
  # the hour is noise and the day is the useful thing.
  FORMATS = {
    today: :row_time,
    yesterday: :row_time,
    earlier: :row_day,
    older: :row_date
  }.freeze

  def initialize(received_at)
    @received_at = received_at
  end

  # The same age said out loud: "4 minutes ago". The Subscriptions page prints
  # it rather than the clock time the feed shows, because a confirmation link
  # expires within a day or two and what the reader needs from a pen row is
  # the distance, not the hour it landed.
  #
  # Distance is unsigned, so a newsletter dated in the future — the clock skew
  # #bucket already allows for — reads as though it were that far past. A
  # freshness line one Date header can make wrong is a smaller problem than
  # printing a negative.
  def in_words
    I18n.t("newsletters.age", duration: time_ago_in_words(received_at))
  end

  # The clock face this age is printed with, chosen by the bucket it falls in
  # rather than beside it — so the two cannot disagree.
  def timestamp
    I18n.l(received_at, format: FORMATS.fetch(bucket))
  end

  # Open at the top: received_at comes from the sender's Date header, so a
  # skewed clock or a scheduled send can date a newsletter in the future.
  # Anything not in the past belongs at the top of the feed rather than
  # nowhere.
  def bucket
    return :today if received_at >= Date.current.beginning_of_day
    return :yesterday if received_at >= Date.yesterday.beginning_of_day
    return :earlier if received_at >= WINDOW.ago

    :older
  end

  private

  attr_reader :received_at
end
