# Whether a newsletter was laid out or written.
#
# The reader strips the sender's styling and stacks everything into one
# column, which is right for prose and wrong for a design. A two-column story
# grid keeps each image next to the headline it belongs to using nothing but
# geometry, and stacking it throws that away — the reader ends up showing the
# wrong picture for every story. Those newsletters are better read as they
# were sent, in the sandboxed frame.
#
# Read from structure rather than from the words: it costs one pass over a
# document the caller has already parsed, gives the same answer every time,
# and needs nothing at ingest that the app does not already have open.
#
# Reads Newsletter::Body's scrubbed document, so a tracking beacon sitting in
# a cell of its own cannot make a single column look like a grid.
class Newsletter::Shape
  # One table is a newsletter written as a list of blocks, and reads correctly
  # once the cells stack. Three is an ESP building a fixed-width canvas: an
  # outer table for the page, an inner one for the column, more inside that.
  DESIGNED_DEPTH = 3

  # A row is a grid when more than one of its cells carries something. Spacer
  # and empty cells do not count — padding the edges of a fixed-width canvas
  # is what most of them are for, and counting them would read every padded
  # single column as a grid.
  #
  # Here rather than in Newsletter::LeadImage, which asks the same question of
  # one row, so the two cannot drift into disagreeing: a newsletter read as
  # prose has to be one whose images the reader is willing to promote.
  def self.grid_row?(row)
    row.element_children
      .select { |child| %w[td th].include?(child.name) }
      .count { |cell| cell.text.strip.present? || cell.css("img").any? } > 1
  end

  def initialize(body)
    @body = body
  end

  def designed?
    any_grid_row? || nesting >= DESIGNED_DEPTH
  end

  private

  attr_reader :body

  def any_grid_row?
    document.css("tr").any? { |row| Newsletter::Shape.grid_row?(row) }
  end

  def nesting
    document.css("table").map { |table| table.ancestors("table").length + 1 }.max.to_i
  end

  def document
    body.document
  end
end
