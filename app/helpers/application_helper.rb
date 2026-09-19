module ApplicationHelper
  # The address subscriptions are pointed at. A helper rather than a reach for
  # Rails.configuration from the template — see .claude/rules/views.md.
  def inbound_address
    Rails.configuration.x.inbound_address
  end

  # Where the source lives. A helper for the same reason inbound_address is one.
  def source_url
    Rails.configuration.x.source_url
  end

  # The mark's stroke weight compensates for size: it thickens as the mark
  # shrinks, so the brackets still read at favicon scale. Set on the <svg>
  # rather than per path, which is what `application/mark` does with this.
  def mark_stroke_width(size)
    return 7 if size <= 16
    return 6 if size <= 22
    return 5 if size <= 30

    4
  end
end
