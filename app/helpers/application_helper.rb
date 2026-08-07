module ApplicationHelper
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
