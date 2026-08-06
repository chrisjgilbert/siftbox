# Display logic for one newsletter, built in the controller and used in the
# views, so no template has to format a date or assemble a sender line.
class Newsletter::Presenter
  delegate :subject, :snippet, :sender_domain, :body_html, :read?, :to_param,
    to: :newsletter

  def initialize(newsletter)
    @newsletter = newsletter
  end

  def title
    "#{sender} — #{subject}"
  end

  def sender
    newsletter.sender_name.presence || newsletter.sender_email
  end

  def timestamp
    if arrived_today_or_yesterday?
      I18n.l(newsletter.received_at, format: :row_time)
    elsif arrived_this_week?
      I18n.l(newsletter.received_at, format: :row_day)
    else
      I18n.l(newsletter.received_at, format: :row_date)
    end
  end

  def received_line
    I18n.t(
      "newsletters.show.received",
      date: I18n.l(newsletter.received_at, format: :received_date),
      time: I18n.l(newsletter.received_at, format: :received_time)
    )
  end

  # The show view reads each neighbour three times — the guard, the title and
  # the link. `defined?` rather than `||=` so a nil neighbour is remembered
  # too, instead of re-querying on every read.
  def newer
    return @_newer if defined?(@_newer)

    @_newer = present(newsletter.newer)
  end

  def older
    return @_older if defined?(@_older)

    @_older = present(newsletter.older)
  end

  private

  attr_reader :newsletter

  def present(other)
    return if other.nil?

    Newsletter::Presenter.new(other)
  end

  def arrived_today_or_yesterday?
    newsletter.received_at >= Date.yesterday.beginning_of_day
  end

  def arrived_this_week?
    newsletter.received_at >= Feed::WINDOW.ago
  end
end
