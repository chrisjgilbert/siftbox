# Whether an email is the double-opt-in confirmation a subscription sends
# back, and so belongs in the pen rather than in an edition.
#
# Asked once, at ingest, and again by the backfill over mail stored before
# this existed. It answers the question only — holding is Newsletter#hold's
# job, and the two endings are the reader's.
#
# A heuristic, and the PRD says so: a miss announces itself as a deadpan line
# in the next edition, and a false positive sits in the pen one click from
# release. Good, not perfect.
#
# Not to be confused with the extraction docs/briefing-followups.md rejected
# under this name — the pen's timestamps, verbs and predicates stay on
# Newsletter, and nothing here writes anything.
class Newsletter::Confirmation
  # The set to tune. Both nouns and both verbs are listed because the
  # boundaries below match whole words: "confirmation" is not a match for
  # "confirm".
  PHRASES = [
    "activate",
    "complete your sign up",
    "confirm",
    "confirmation",
    "finish signing up",
    "opt in",
    "verification",
    "verify"
  ].freeze

  # Plain words, so nothing here is escaped. A space inside a phrase matches
  # a hyphen or nothing at all, because a sender writes "sign up", "sign-up"
  # and "signup" in one email and means the same thing three times.
  #
  # The word boundaries at the ends are what keep the set off ordinary
  # newsletter writing. "Confirmed:" opens headlines, every other essay
  # reaches for activation energy, and neither is a match.
  SUBJECT = Regexp.union(
    PHRASES.map { |phrase| /\b#{phrase.split.join('[\s-]*')}\b/i }
  ).freeze

  def initialize(newsletter)
    @newsletter = newsletter
  end

  def detected?
    subject_reads_as_confirmation? && first_time_sender?
  end

  private

  attr_reader :newsletter

  # to_s because nothing raised in here may lose a newsletter: ingest runs
  # this inside the transaction that stores the mail.
  def subject_reads_as_confirmation?
    SUBJECT.match?(newsletter.subject.to_s)
  end

  # Content from this address, not mail from this address. Confirmations
  # arrive from the platform (no-reply@substack.com, Mailchimp) rather than
  # from the newsletter itself, so counting an earlier confirmation still
  # sitting in the pen — or one dismissed once it was clicked — would make
  # the platform an established sender and miss every subscription after the
  # first. Released mail does count: the reader saying "this is a newsletter"
  # is the strongest evidence there is that the address sends them.
  #
  # Strictly earlier, so the newsletter never counts against itself. Ingest
  # asks after the insert and the backfill asks weeks later; both get the
  # answer ingest would have given before the row existed.
  def first_time_sender?
    earlier_content.none?
  end

  def earlier_content
    Newsletter.content
      .where(sender_email: newsletter.sender_email)
      .where("received_at < ?", newsletter.received_at)
  end
end
