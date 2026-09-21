# A published edition as words to be spoken: the masthead, each section's
# heading, and every story's headline and body in the order the page prints
# them.
#
# The editor's prose goes through untouched, and that is the whole bet of this
# first version rather than an omission. Edition::Prompt already forbids
# markdown, HTML, links and bullets, and already asks for attribution inside
# the sentence — "Money Stuff and The Diff both read the S-1" — so what the
# editor writes is plain sentences with the sources named in them. Nothing here
# rewrites it for the ear, and whether it needs rewriting is a question that
# can only be answered by listening to a few editions, not by reading a script.
#
# Two things are changed, both because they are unspeakable rather than because
# they read awkwardly. "No. 14" is the masthead's abbreviation and is the word
# "no" out loud, so the opening line is built here instead. And a headline
# carries no final stop, so a synthesiser runs it into the body's first
# sentence; one is added when the editor left none.
#
# One thing is dropped: the citation line under each story. It is an index of
# sender names, which is furniture for the eye and a list of proper nouns read
# aloud, and the link it carries only means anything on the page it is on.
#
# The section order and the headings come from Edition::Presenter rather than
# from a list here. docs/briefing-followups.md already records two places
# knowing that order — the presenter and EditionTranscript — as a wart, and a
# third would be worse. What Presenter hands over is a heading and the stories
# under it; the story presenters it wraps them in answer #headline and #body by
# delegation, and their citation methods simply go unasked.
class Edition::Script
  # What counts as a sentence already ended. Enough for a headline, which is
  # the only place this is asked: a body is prose and ends in a stop of its own.
  ENDINGS = [ ".", "!", "?", ":" ].freeze

  def initialize(edition)
    @edition = edition
  end

  def text
    ([ masthead ] + spoken_sections).join("\n\n")
  end

  private

  attr_reader :edition

  # Through the locale file like every other reader-facing string, so the
  # wording of the one line this app writes rather than quotes can be changed
  # without touching Ruby.
  def masthead
    I18n.t("editions.script.masthead", number: edition.number, date: date)
  end

  # Asked of the presenter rather than formatted again here. It is the same
  # day in the same format the masthead prints, and a second call to I18n.l
  # would be a third owner of that format — the thing the class comment above
  # cites docs/briefing-followups.md about.
  def date
    presenter.date
  end

  def spoken_sections
    presenter.sections.flat_map { |section| spoken_section(section) }
  end

  def spoken_section(section)
    [ closed(section.heading) ] + section.stories.flat_map { |story| spoken_story(story) }
  end

  def spoken_story(story)
    return [ story.body ] unless story.headline?

    [ closed(story.headline), story.body ]
  end

  def closed(line)
    return line if line.end_with?(*ENDINGS)

    "#{line}."
  end

  def presenter
    @_presenter ||= Edition::Presenter.new(edition)
  end
end
