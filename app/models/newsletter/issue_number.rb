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

  def to_s
    PATTERNS.filter_map { |pattern| subject.to_s[pattern, 1] }.first.to_s
  end

  private

  attr_reader :subject
end
