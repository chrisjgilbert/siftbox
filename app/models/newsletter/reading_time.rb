# How long the reader's data strip says a newsletter will take.
#
# Counts Newsletter::Body's text rather than the raw HTML's: a newsletter
# opens with a stylesheet far longer than its prose, and counting that would
# put every issue at twenty minutes.
class Newsletter::ReadingTime
  WORDS_A_MINUTE = 200

  def initialize(html)
    @html = html
  end

  # Floored at one. "0 min" tells the reader nothing, and every newsletter
  # takes some time to read.
  def minutes
    [ (words / WORDS_A_MINUTE.to_f).round, 1 ].max
  end

  private

  attr_reader :html

  def words
    Newsletter::Body.new(html).text.split.length
  end
end
