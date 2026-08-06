# Display logic for one newsletter, built in the controller and used in the
# views, so no template has to format a date or assemble a sender line.
class Newsletter::Presenter
  delegate :id, :subject, :snippet, :sender_domain, :body_html, :read?,
    :to_model, :to_param, to: :newsletter

  def initialize(newsletter)
    @newsletter = newsletter
  end

  def sender_line
    "#{sender} — #{sender_domain}"
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

  def newer
    present(newsletter.newer)
  end

  def older
    present(newsletter.older)
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
