# The issue number a newsletter puts in its own subject, when it does.
#
# Two forms cover almost every list: "#742: ..." and "Issue 612 — ...".
# A bare number is left alone, because a version, a year and a price all look
# the same from here — the data strip drops the field rather than inventing
# one.
class Newsletter::IssueNumber
  PATTERNS = [ /#(\d+)/, /\bissue\s+(\d+)/i ].freeze

  def initialize(subject)
    @subject = subject
  end

  # Whichever form appears first in the subject, not whichever pattern is
  # listed first. "Issue 612 — the #1 thing you should know" is issue 612, and
  # resolving by pattern order would file it as issue 1.
  def to_s
    earliest = matches.min_by { |match| match.begin(0) }
    return "" if earliest.nil?

    earliest[1]
  end

  private

  attr_reader :subject

  def matches
    PATTERNS.filter_map { |pattern| subject.to_s.match(pattern) }
  end
end
