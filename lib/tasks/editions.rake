namespace :edition do
  desc "Compose an edition from the last DAYS days of stored newsletters and print it"
  task :backtest, [ :days ] => :environment do |_task, arguments|
    raise "Development only" unless Rails.env.development?

    Backtest.stored((arguments[:days] || Backtest::DEFAULT_DAYS).to_i)
  end

  desc "Compose an edition from the synthetic corpus and print it"
  task corpus: :environment do
    raise "Development only" unless Rails.env.development?

    Backtest.corpus
  end
end

# Milestone 0's tool, and the only one there is until the schedule and the
# pages exist: compose an edition from a window and dump it, so the PRD's five
# checks — clustering, attribution, coverage, selection, classification — are
# made by reading rather than assumed. Iterating the prompt means running this
# over several windows and reading the output, which is why the format it
# prints (EditionTranscript) is taken as seriously as the code that composes.
#
# Two ways in. `edition:corpus` reads the synthetic corpus, whose expected
# answers are written down in lib/edition_corpus.rb, and is the one to run
# first: it says whether a real model clusters mail it has never seen into the
# stories a person would. `edition:backtest[3]` reads real stored newsletters,
# which is the judgement that actually decides whether story-first survives.
#
# Both need ANTHROPIC_API_KEY in the environment, and both cost real money —
# tens of cents a run, printed in the masthead.
module Backtest
  DEFAULT_DAYS = 1

  # Nothing is kept. A backtest rehearses an edition rather than publishing
  # one: the same window gets read again after the next prompt change, and a
  # dev database filling up with editions dated today — one per attempt, each
  # colliding with the last on a unique index — would make that the awkward
  # part of iterating. The corpus's newsletters are created inside the same
  # transaction and go with it, so running this leaves the database exactly as
  # it was found.
  def self.corpus
    Edition.transaction do
      ingested = EditionCorpus.ingest
      newsletters = Newsletter.content.where(id: ingested.values.map(&:id)).oldest_first.to_a

      rehearse(newsletters, newsletters.first.received_at..Time.current)
      raise ActiveRecord::Rollback
    end
  end

  # The window is a received_at range and nothing else. The real one has a
  # second clause — mail released out of the confirmation pen carries a
  # received_at behind the watermark, so it is picked up on released_at
  # instead — but that arrives with the watermark itself in the publishing
  # milestone, and a backtest chooses its range by hand anyway. Through
  # .content, which is what keeps held confirmations out.
  def self.stored(days)
    window = days.days.ago..Time.current
    newsletters = Newsletter.content.where(received_at: window).oldest_first.to_a

    Edition.transaction do
      rehearse(newsletters, window)
      raise ActiveRecord::Rollback
    end
  end

  def self.rehearse(newsletters, window)
    return puts "No newsletters in that window — an empty window skips silently." if newsletters.empty?
    return if published?(window)

    puts "Reading #{newsletters.length} newsletters. Expect a minute or two."
    puts EditionTranscript.new(composed(newsletters, window), newsletters).text
    puts "Nothing was saved. A backtest rehearses an edition; it does not publish one."
  end

  # A rehearsal is validated exactly as the real composition is, so a day that
  # already has an edition stops it rather than failing later on the unique
  # index with a message about a column. Re-reading a window whose edition
  # exists is regeneration, which is the publishing milestone's job and needs
  # to decide what happens to the edition already there.
  def self.published?(window)
    day = window.end.to_date
    return false unless Edition.exists?(published_on: day)

    puts "An edition is already published for #{day}, and a rehearsal cannot borrow its date."
    true
  end

  # Read back through the association the edition page will use, so the
  # transcript's walk over every story's citations is four queries rather than
  # one per story.
  def self.composed(newsletters, window)
    edition = Edition::Editor.new(rehearsal(window), newsletters).compose

    Edition.includes(stories: :newsletters).find(edition.id)
  end

  # Numbered and dated as the real thing would be, because the masthead is
  # part of what is being judged. Both are thrown away with the transaction —
  # allocating a number for real belongs on Edition, in the milestone that
  # publishes one.
  def self.rehearsal(window)
    Edition.new(
      number: Edition.maximum(:number).to_i + 1, published_at: Time.current,
      published_on: window.end.to_date, window_started_at: window.begin,
      window_ended_at: window.end
    )
  end
end
