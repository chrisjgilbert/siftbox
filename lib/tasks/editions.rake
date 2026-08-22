namespace :edition do
  desc "Compose an edition from the newsletters the next one would cover and print it"
  task backtest: :environment do
    raise "Development only" unless Rails.env.development?

    Backtest.stored
  end

  desc "Compose an edition from the synthetic corpus and print it"
  task corpus: :environment do
    raise "Development only" unless Rails.env.development?

    Backtest.corpus
  end

  desc "Rewrite the edition published on DATE (default: the latest) with today's prompt"
  task :regenerate, [ :date ] => :environment do |_task, arguments|
    raise "Development only" unless Rails.env.development?

    Regeneration.rewrite(arguments[:date])
  end
end

# Judging what the editor writes, which is done by reading it: compose an
# edition from a window and dump it, so the PRD's five checks — clustering,
# attribution, coverage, selection, classification — are made by reading
# rather than assumed. Iterating the prompt means running one of these over
# several windows and reading the output, which is why the format it prints
# (EditionTranscript) is taken as seriously as the code that composes.
#
# Three ways in. `edition:corpus` reads the synthetic corpus, whose expected
# answers are written down in lib/edition_corpus.rb, and is the one to run
# first: it says whether a real model clusters mail it has never seen into the
# stories a person would. `edition:backtest` reads real stored newsletters —
# the judgement that actually decides whether story-first survives — over the
# window the 07:00 job would compose from right now, keeping nothing.
# `edition:regenerate` is the one to reach for once that job has run: today's
# window already has an edition and its date is taken, so the way to see a new
# prompt against the same mail is to write over it.
#
# All three need ANTHROPIC_API_KEY in the environment, and all three cost real
# money — tens of cents a run, printed in the masthead.
module Backtest
  EMPTY_WINDOW =
    "Nothing since the last edition closed — an empty window skips silently.".freeze

  # Nothing is kept. A backtest rehearses an edition rather than publishing
  # one: the same window gets read again after the next prompt change, and a
  # dev database filling up with editions dated today — one per attempt, each
  # colliding with the last on a unique index — would make that the awkward
  # part of iterating. The corpus's newsletters are created inside the same
  # transaction and go with it, so running this leaves the database exactly as
  # it was found.
  # No posts: the corpus is seven newsletters chosen to disagree with each
  # other, and what it pins is the clustering across them. A blog post is
  # another source of prose rather than another kind of disagreement, so
  # edition:backtest is where posts get read.
  def self.corpus
    Edition.transaction do
      ingested = EditionCorpus.ingest
      newsletters = Newsletter.content.where(id: ingested.values.map(&:id)).oldest_first.to_a
      sources = Edition::Sources.new(newsletters: newsletters, posts: [])

      rehearse(sources, rehearsal(newsletters.first.received_at, Time.current))
      raise ActiveRecord::Rollback
    end
  end

  # The window the job would compose from, built by the job's own object
  # rather than by a range of this task's choosing: a rehearsal is only worth
  # reading if what it rehearses is what runs at 07:00 — two clauses so that
  # mail released out of the confirmation pen is picked up on released_at,
  # .content so that mail still in the pen is not, and the watermark rather
  # than a span.
  #
  # Which is why the DAYS argument is gone. A hand-picked range is a window
  # nothing will ever compose, and after the first edition it is also a window
  # that overlaps the last one. Reading more mail than the last edition left
  # over is what edition:corpus and edition:regenerate are for.
  def self.stored
    window = Edition::Window.new(Time.current)

    Edition.transaction do
      rehearse(window.sources, window.edition)
      raise ActiveRecord::Rollback
    end
  end

  def self.rehearse(sources, edition)
    return puts EMPTY_WINDOW if sources.empty?
    return if published?(edition.published_on)

    puts "Reading #{reading(sources)}. Expect a minute or two."
    puts EditionTranscript.new(composed(sources, edition), sources).text
    puts "Nothing was saved. A backtest rehearses an edition; it does not publish one."
  end

  # Counted apart because they are read apart: a morning of twenty
  # newsletters and one post is a different rehearsal from the other way
  # round, and the whole point of a backtest is knowing what went in.
  def self.reading(sources)
    "#{sources.newsletters.length} newsletters and #{sources.posts.length} posts"
  end

  # A rehearsal is validated exactly as the real composition is, so a day that
  # already has an edition stops it here rather than after the request, on the
  # unique index, with a message about a column. The guard stays now that
  # regeneration exists rather than deferring to it, because the two are
  # different jobs: this one keeps nothing, and rewriting a published edition
  # is a thing to be asked for by name.
  def self.published?(day)
    return false unless Edition.exists?(published_on: day)

    puts "An edition is already published for #{day}; rehearsing cannot borrow its date. " \
      "Use edition:regenerate to write over it with the current prompt."
    true
  end

  # Read back through the association the edition page will use, so the
  # transcript's walk over every story's citations is four queries rather than
  # one per story.
  def self.composed(sources, edition)
    composed = Edition::Editor.new(edition, sources).compose

    Edition.for_reading.find(composed.id)
  end

  # The corpus's own edition, numbered and dated as the real thing would be
  # because the masthead is part of what is being judged, and thrown away with
  # the transaction. The corpus picks its newsletters by name rather than by
  # window — that is the point of it — so it is the one rehearsal that cannot
  # ask Edition::Window for its edition.
  def self.rehearsal(started_at, ended_at)
    Edition.new(
      number: Edition.next_number, published_at: ended_at,
      published_on: ended_at.to_date, window_started_at: started_at,
      window_ended_at: ended_at
    )
  end
end

# Composing a published edition again from the same mail, with whatever the
# prompt says today — the PRD's dev-only regenerate task. What it does to the
# row it rewrites, and why the stored raw response is not replayed, is in
# lib/edition_regeneration.rb. The short version: the edition is destroyed and
# another written in its place, carrying the same number, day and window, and
# there is no undo.
module Regeneration
  def self.rewrite(date)
    edition = chosen(date)
    return puts "No edition to rewrite." if edition.nil?

    regeneration = EditionRegeneration.new(edition)
    puts opening(edition, regeneration.sources)
    puts EditionTranscript.new(regeneration.rewrite, regeneration.sources).text
    puts "No. #{edition.number} is now the edition above. Its number, its day and " \
      "its window are unchanged, so the next composition still starts where it closed."
  end

  # The latest edition by default, which is the one a prompt change is
  # normally being judged against. A date picks any other: it is what the
  # masthead prints and what the unique index counts one edition a day by.
  def self.chosen(date)
    return Edition.latest if date.blank?

    Edition.find_by(published_on: Date.parse(date))
  end

  # Said before the request rather than after it, because this is the moment
  # to stop: the old copy, its provenance and its stored response are about to
  # be destroyed, and nothing here writes them anywhere else first.
  def self.opening(edition, sources)
    "Rewriting no. #{edition.number} of #{edition.published_on} over " \
      "#{sources.newsletters.length} newsletters and #{sources.posts.length} posts. " \
      "It was written by #{edition.editor_model} on prompt " \
      "#{edition.prompt_version}, and that row goes with it. Expect a minute or two."
  end
end
