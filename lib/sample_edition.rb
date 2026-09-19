# The edition a fresh development database opens on, written from the
# newsletters lib/tasks/sample_data.rake creates — with no model, no key and
# no request.
#
# sample_data:load filled the archive and composed nothing, so a fresh
# environment opened on "No editions yet" until a key was added and 07:00
# came round. The edition page is the app, and the README's screenshot is of
# it, so the sample task writes one. It is a picture of an edition rather
# than a composed one: fixed prose in the shape the real page draws — a lead
# with a headline, Briefly lines without, a reading list entry with one — and
# editor_model and prompt_version both read "sample", so the row can never
# be mistaken for the model's work.
#
# Written the way Edition::Editor#record writes: the graph built in memory,
# citations and all, and one save!, so there is no moment at which an
# edition exists without its stories.
#
# Development material. Nothing the reader's browser reaches calls it.
class SampleEdition
  # Which newsletters each story cites, by position in the list the task
  # creates: the lead reads the first two, which both carry the parser
  # release; each Briefly line reads one; the reading list entry reads the
  # last. Every newsletter is cited by exactly one story, which is the
  # completeness guarantee the real editor is held to.
  #
  # No headline on a Briefly line: the column defaults to "" and the page
  # draws no heading over an empty string.
  STORIES = [
    {
      section: Edition::Story::LEAD, cites: [ 0, 1 ],
      headline: "Ruby 3.4 ships with a rewritten parser",
      body: "Both newsletters lead with the parser rewrite, the largest " \
        "change to the language's front end in a decade: error messages " \
        "now point at the token that failed, incremental parsing makes " \
        "editor tooling viable, and the grammar is a readable artefact of " \
        "its own. They agree on what changed and part on what it means. " \
        "One calls the migration note required reading for anything that " \
        "walks the syntax tree; the other says most gems will never notice."
    },
    {
      section: Edition::Story::BRIEFLY, cites: [ 2 ],
      body: "Postgres 18 adds skip scan to multi-column indexes, so a " \
        "query that leaves out the leading column can use the index at all " \
        "rather than falling back to a scan."
    },
    {
      section: Edition::Story::BRIEFLY, cites: [ 3 ],
      body: "A short argument for media that has no idea whether you " \
        "finished it, and for reading things that do not want your " \
        "attention."
    },
    {
      section: Edition::Story::READING_LIST, cites: [ 4 ],
      headline: "Five articles worth your evening",
      body: "Lighthouse keepers, a very long bridge, and why nobody agrees " \
        "what a sandwich is. The kind of reading that goes better slowly; " \
        "keep it for a quiet hour."
    }
  ].freeze

  # No model, no prompt, no tokens: what the row says about how it was
  # written is that it was not.
  PROVENANCE = { editor_model: "sample", prompt_version: "sample" }.freeze

  # The newsletters in the order the task lists them, which is the order
  # STORIES cites them by.
  def initialize(newsletters)
    @newsletters = newsletters
  end

  def write
    edition = Edition.new(identity.merge(PROVENANCE))
    stories.each_with_index { |story, index| build(edition, story, index + 1) }

    edition.save!
    edition
  end

  private

  attr_reader :newsletters

  # STORIES, once it is known to cover the list it was handed. The coupling
  # is by position across two files, so a newsletter added to the task's
  # list has no story here until one is written — and fetch only catches the
  # list being shorter than STORIES expects, never longer. The task fails on
  # this rather than writing an edition that quietly leaves one out, which is
  # the failure the real editor exists to refuse.
  def stories
    uncited = newsletters.each_index.to_a - cited
    return STORIES if uncited.empty?

    raise ArgumentError, "no story cites newsletter #{uncited.join(", ")}"
  end

  def cited
    STORIES.flat_map { |story| story.fetch(:cites) }
  end

  # What Edition::Window#edition sets, and Edition validates all of it. The
  # window opens at the oldest newsletter's arrival and closes now, which is
  # also when it is published. Nothing reads the two columns back as a range
  # — EditionRegeneration recovers a window from its citations — so the
  # sample makes no attempt to sit the oldest newsletter inside the exclusive
  # lower bound Edition::Window queries by; the citations are the window.
  def identity
    {
      number: Edition.next_number, published_at: closed_at,
      published_on: closed_at.to_date, window_ended_at: closed_at,
      window_started_at: newsletters.map(&:received_at).min
    }
  end

  # Read once, so the publication time and the window's close cannot
  # disagree — the reason Edition::Window takes its closing moment rather
  # than reading the clock.
  def closed_at
    @_closed_at ||= Time.current
  end

  # Positions run across the whole edition, the way Edition::Editor numbers
  # them. Cited by object, because belongs_to would otherwise load each
  # newsletter back out to satisfy its presence check.
  def build(edition, story, position)
    attributes = story.except(:cites).merge(position: position)
    built = edition.stories.build(attributes)

    story.fetch(:cites).each do |index|
      built.citations.build(newsletter: newsletters.fetch(index))
    end
  end
end
