# The archive, read again with the confirmation detector that did not exist
# when it was stored.
#
# Detection runs at ingest, so the pen starts empty on the day it ships while
# every confirmation the reader has ever received sits in the archive behind
# it. This is the one-off deploy step that fills it, the way
# `lead_images:backfill` filled a column the archive predates.
#
# Safe to run again, twice over: `Newsletter.never_held` has stopped matching
# anything this held, and `Newsletter#hold` keeps the first stamp anyway. What
# it is not is reversible — the undo for a hold is #release, and releasing
# three-week-old mail carries it into tomorrow's edition. Hence
# `confirmations:preview`, which does the whole run inside a transaction and
# rolls it back.
class ConfirmationBackfill
  # Ids, read once, before anything is held: holding shrinks the set this
  # query answers, so a second reading would disagree with the first about
  # how much mail was looked at.
  #
  # Ids rather than rows because the walk reloads them in batches. The bodies
  # in an archive of newsletters run to hundreds of kilobytes each, and
  # nothing here reads one.
  def candidates
    @_candidates ||= Newsletter.never_held.uncited.pluck(:id)
  end

  # The newsletters it held, for the task to print. Batched by id, which is
  # ingest order — near enough to received_at order that the only mail the
  # two disagree about is mail delivered late, and the detector tolerates
  # that.
  def hold
    stored.find_each.filter_map { |newsletter| confirmation(newsletter) }
  end

  private

  def stored
    Newsletter.where(id: candidates)
  end

  # The newsletter, now held, or nil. Held here inside the walk rather than
  # collected and held afterwards, because each hold changes the answer for
  # the mail behind it: two subscriptions confirmed through the same
  # no-reply address are both first-time senders only while the first
  # confirmation is not counted as content.
  def confirmation(newsletter)
    return unless Newsletter::Confirmation.new(newsletter).detected?

    newsletter.hold
    newsletter
  end
end
