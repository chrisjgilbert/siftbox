# How long the reader's data strip says a newsletter will take.
#
# Counts Newsletter::Body's text rather than the raw HTML's: a newsletter
# opens with a stylesheet far longer than its prose, and counting that would
# put every issue at twenty minutes.
class Newsletter::ReadingTime
  WORDS_A_MINUTE = 200

  # Takes a Newsletter::Body rather than a string, the same way
  # Newsletter::LeadImage does, so the reader can hand both of them the one
  # body it has already parsed. Building its own cost a second Loofah pass
  # over the whole newsletter — measured at 73ms of a 163ms render on a 61KB
  # body, for a word count.
  def initialize(body)
    @body = body
  end

  # Floored at one. "0 min" tells the reader nothing, and every newsletter
  # takes some time to read.
  def minutes
    [ (words / WORDS_A_MINUTE.to_f).round, 1 ].max
  end

  private

  attr_reader :body

  def words
    body.text.split.length
  end
end
