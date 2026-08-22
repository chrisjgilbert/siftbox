# A published edition composed again from the same sources, with whatever the
# prompt says today.
#
# The PRD's tool for iterating on the prompt after the schedule ships: an
# edition is immutable and a prompt change applies from the next one, so the
# only way to see what a new wording does to yesterday's mail — the same
# reading the corpus and the backtest are for — is a task that is allowed to
# break that rule, in development, on purpose. Everything it needs is on the
# row already: "model name, prompt version, token counts, raw response —
# enough to debug a bad edition and regenerate after a prompt change without
# re-fetching anything."
#
# The stored raw_response is not replayed. A prompt change that does not reach
# the model changes nothing, so this is a second full-price request; what the
# stored response is for is reading the old answer back, and it goes with the
# row it is on. Copy it out first if the two answers are to be compared.
#
# Not safe against anything but a development database, and the guard on the
# rake task is the environment rather than the data — a development database
# restored from a production dump is production data, and this destroys the
# edition it rewrites.
class EditionRegeneration
  # An edition that cites nothing cannot be regenerated from itself, and the
  # failure has to be here: Edition::Editor's completeness check passes
  # vacuously over an empty set, so it would accept any answer at all and
  # replace a published edition with an empty one. The same gap
  # Edition::CompositionJob closes by skipping an empty window.
  Empty = Class.new(StandardError)

  # The client is injected the way Edition::Editor and Edition::Draft take it,
  # so a spec can hand this a fake rather than stub HTTP.
  def initialize(edition, client: nil)
    @edition = edition
    @client = client
  end

  # The window the edition covered, recovered from its citations rather than
  # from the dates on the row. Completeness makes the two the same set at
  # composition — every newsletter in the window is cited by some story, and
  # an id that was not in the window is refused — and only the citations stay
  # that way afterwards: window_started_at and window_ended_at describe the
  # received_at axis only, so re-running them as a range would drop every
  # newsletter released out of the confirmation pen and pick up whatever has
  # arrived since.
  #
  # Not through Newsletter.content either. The pen decides what a new window
  # may take; this window is history, and a newsletter held after the fact was
  # still what these stories were written from.
  def sources
    @_sources ||= Edition::Sources.new(newsletters: cited_mail, posts: cited_posts)
  end

  # Loaded before the destroy on purpose — the citations that name them are
  # about to go with it.
  def rewrite
    raise Empty, "no. #{edition.number} cites nothing" if sources.empty?

    replace
  end

  private

  attr_reader :edition, :client

  # One transaction over the destroy and the composition, so a model that
  # cannot answer leaves the reader with the edition they already had rather
  # than with none. Nothing wraps this in a transaction of its own, so it is
  # the outermost one and its rollback is the real thing.
  def replace
    Edition.transaction do
      identity = edition.slice(
        :number, :published_at, :published_on, :window_ended_at, :window_started_at
      )
      edition.destroy!

      loaded(Edition::Editor.new(Edition.new(identity), sources, client: client).compose)
    end
  end

  # Read back through the associations the page will use, so a walk over every
  # story's citations is a handful of queries rather than one per story.
  def loaded(composed)
    Edition.includes(stories: [ :blog_posts, :newsletters ]).find(composed.id)
  end

  def cited_mail
    Newsletter.where(id: cited(:newsletter_id)).oldest_first.to_a
  end

  def cited_posts
    Blog::Post.where(id: cited(:blog_post_id)).oldest_first.to_a
  end

  # One column at a time. A citation names one source and leaves the other
  # column NULL, so a subquery selecting both would hand each side the other's
  # nils — harmless inside an IN, which no NULL matches, but only by accident.
  def cited(column)
    Edition::Citation.where(edition_story_id: edition.story_ids).select(column)
  end
end
