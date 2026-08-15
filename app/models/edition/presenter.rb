# Display logic for one edition, built in the controller and used in the view,
# so no template has to format a date, name a section or decide which of them
# to draw.
#
# The three section readers stay on Edition and are wrapped here rather than
# moved. What they answer — which stories the editor filed where — is the
# classification the editor made, and three things that are not pages already
# ask for it: Edition::Editor's own specs, the corpus, and EditionTranscript.
# What is layout is this class: the order the sections read, the words above
# them, and dropping one the edition has nothing for.
class Edition::Presenter
  # One section as the page draws it. The name is the section's own word, held
  # here so a template need not reach for Edition::Story::LEAD — see
  # .claude/rules/views.md on a view referencing a model class.
  Section = Struct.new(:name, :heading, :stories)

  delegate :to_param, to: :edition

  def initialize(edition)
    @edition = edition
  end

  # "No. 1 · Tuesday 11 August" — what an edition is called. Sentence case here
  # and uppercased in CSS, because JetBrains Mono is always uppercase and the
  # locale file is not the place to shout: docs/siftbox-redesign.md §2.
  def masthead
    I18n.t("editions.masthead", number: number, date: date)
  end

  # The two halves the masthead is built from, because the archive draws them
  # in columns of their own: the number is the edition's name, and the day is
  # what the list is ordered by and what a reader scans down.
  def number
    I18n.t("editions.number", number: edition.number)
  end

  # The day covered, never the wall clock that composed it. An edition
  # composed late is still the earlier day's edition.
  def date
    I18n.l(edition.published_on, format: :edition_masthead)
  end

  # Lead stories, then Briefly, then the reading list. A section with nothing
  # in it is left out entirely rather than drawn as a heading over nothing —
  # which on a quiet day is what happens to the reading list.
  def sections
    @_sections ||= [ lead, briefly, reading_list ].compact
  end

  private

  attr_reader :edition

  def lead
    section(Edition::Story::LEAD, edition.lead_stories)
  end

  def briefly
    section(Edition::Story::BRIEFLY, edition.briefly)
  end

  def reading_list
    section(Edition::Story::READING_LIST, edition.reading_list)
  end

  def section(name, stories)
    return if stories.empty?

    Section.new(name, I18n.t("editions.sections.#{name}"), present(stories))
  end

  def present(stories)
    stories.map { |story| Edition::Story::Presenter.new(story) }
  end
end
