# Display logic for one newsletter, built in the controller and used in the
# views, so no template has to format a date or assemble a sender line.
class Newsletter::Presenter
  # Which timestamp format each row gets. Keyed by Newsletter::Age so the
  # format always agrees with the group heading the row sits under.
  TIMESTAMP_FORMATS = {
    today: :row_time,
    yesterday: :row_time,
    earlier: :row_day,
    older: :row_date
  }.freeze

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
    I18n.l(newsletter.received_at, format: TIMESTAMP_FORMATS.fetch(age.bucket))
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

  def age
    Newsletter::Age.new(newsletter.received_at)
  end

  def present(other)
    return if other.nil?

    Newsletter::Presenter.new(other)
  end
end
