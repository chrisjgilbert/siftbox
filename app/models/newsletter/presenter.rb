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

  delegate :lead_image?, :lead_image_url, :read?, :snippet, :subject,
    :to_param, to: :newsletter

  def initialize(newsletter)
    @newsletter = newsletter
  end

  def title
    "#{sender} — #{subject}"
  end

  # Mail with no From header at all leaves nothing to show, and a row headed
  # by a bare em dash reads as a rendering fault rather than as missing data.
  def sender
    newsletter.sender_name.presence || newsletter.sender_email.presence ||
      I18n.t("newsletters.unknown_sender")
  end

  # Nil rather than "" so the views can drop the em dash with it — the dash
  # belongs to the domain, not between two halves that might both be absent.
  def sender_domain
    newsletter.sender_domain.presence
  end

  def kicker
    return sender if sender_domain.nil?

    I18n.t("newsletters.show.kicker", sender: sender, domain: sender_domain)
  end

  def timestamp
    I18n.l(newsletter.received_at, format: TIMESTAMP_FORMATS.fetch(age.bucket))
  end

  def received_line
    I18n.t(
      "newsletters.show.received",
      stamp: I18n.l(newsletter.received_at, format: :received_stamp)
    )
  end

  # Nil when the subject carries no number, so the data strip drops the field
  # rather than showing a label with nothing after it.
  def issue
    number = Newsletter::IssueNumber.new(subject).to_s
    return if number.blank?

    I18n.t("newsletters.show.issue", number: number)
  end

  def reading_time
    I18n.t(
      "newsletters.show.reading_time",
      minutes: Newsletter::ReadingTime.new(newsletter.body_html).minutes
    )
  end

  # The body without the image the reader promotes above the article. Leaving
  # it in would render the same image twice.
  def body
    lead_image.remainder
  end

  def lead_image_alt
    lead_image.alt
  end

  def newer
    present(newsletter.newer)
  end

  def older
    present(newsletter.older)
  end

  private

  attr_reader :newsletter

  # One instance for both readers, so the body is parsed once per render
  # rather than once for the caption and once for the article.
  def lead_image
    @_lead_image ||= Newsletter::LeadImage.new(reading_body)
  end

  # Built here rather than in the helper, because the view is handed a
  # presenter and .claude/rules/views.md keeps it that way. The sizes let the
  # browser reserve space for an image before it loads; without them every
  # image shifts the text the reader is already looking at.
  def reading_body
    Newsletter::Body.new(
      newsletter.body_html,
      dimensions: Newsletter::ImageDimensions.new(newsletter).to_h
    )
  end

  def age
    Newsletter::Age.new(newsletter.received_at)
  end

  def present(other)
    return if other.nil?

    Newsletter::Presenter.new(other)
  end
end
