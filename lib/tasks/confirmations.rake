namespace :confirmations do
  # A deploy step, once, after the detector ships. Detection runs at ingest,
  # so without this the pen is empty on the first morning while every
  # confirmation the reader has ever received sits in the archive behind it.
  #
  # Idempotent, and safe to run again: what it held is no longer mail the pen
  # has never flagged, and Newsletter#hold keeps its first stamp regardless.
  desc "Hold the confirmations in mail stored before detection existed"
  task backfill: :environment do
    Confirmations.backfill
  end

  # Read this first. A hold is undone by releasing, and releasing mail from
  # three weeks ago carries it into tomorrow's edition — so a phrase set that
  # is one word too greedy costs more than a click here.
  desc "Say what confirmations:backfill would hold, keeping nothing"
  task preview: :environment do
    Confirmations.preview
  end
end

# What the two tasks print. The walk itself is ConfirmationBackfill, in lib,
# where a spec can reach it.
module Confirmations
  def self.backfill
    report(ConfirmationBackfill.new)
  end

  # The whole run, rolled back — the same rehearsal shape as edition:backtest,
  # and honest for the same reason: it is the real walk, holding as it goes,
  # so what it prints is what the backfill would do rather than an
  # approximation of it.
  def self.preview
    Newsletter.transaction do
      report(ConfirmationBackfill.new)
      puts "Nothing was kept. Run confirmations:backfill to hold the mail above."
      raise ActiveRecord::Rollback
    end
  end

  # Every hold named, sender and subject, because the PRD expects the phrase
  # set to be tuned and this is the only place a run of it can be read.
  def self.report(backfill)
    scanned = backfill.candidates.length
    held = backfill.hold

    held.each { |newsletter| puts "  #{newsletter.sender_email}  #{newsletter.subject}" }
    puts "Held #{held.length} of #{scanned} newsletters the pen had never flagged."
  end
end
