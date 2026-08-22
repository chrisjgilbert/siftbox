require "rails_helper"

RSpec.describe EditionCorpus do
  it "ingests every item as a newsletter" do
    ingested = EditionCorpus.ingest

    expect(ingested.values).to all(be_persisted)
  end

  it "keys the ingested newsletters by the name the corpus calls them" do
    ingested = EditionCorpus.ingest

    expect(ingested.keys).to match_array(EditionCorpus.items.map(&:key))
  end

  # Through #hold rather than by writing held_at, because the pen is held
  # together by validations rather than by a database constraint and a bulk
  # write would walk straight past them. Same reason the PRD's backfill has to
  # call the verb.
  it "holds the subscription confirmation" do
    ingested = EditionCorpus.ingest

    expect(ingested.fetch(:whiteboard_confirmation)).to be_held
  end

  # The carve-out the completeness guarantee has, and the whole reason the
  # confirmation is in the corpus: it is kept out by the stored flag the window
  # query reads, not by an instruction in the prompt.
  it "keeps the confirmation out of the set an edition is composed from" do
    ingested = EditionCorpus.ingest

    expect(Newsletter.content).not_to include(ingested.fetch(:whiteboard_confirmation))
  end

  it "leaves every other newsletter in that set" do
    ingested = EditionCorpus.ingest

    expect(Newsletter.content.count).to eq(ingested.length - 1)
  end

  # The reason there is a corpus at all: without several senders on one event,
  # clustering has nothing to collapse and the instruction to surface
  # disagreement rather than resolve it has nothing to bite on.
  it "covers one event from three senders" do
    covering = EditionCorpus.sources(EditionCorpus.story(:tessera))

    expect(covering.map(&:key))
      .to contain_exactly(:stack_weekly, :kernel_notes, :substrate)
  end

  it "carries an evergreen tutorial, a teaser and a singleton as well" do
    natures = EditionCorpus.items.map(&:nature)

    expect(natures).to include(
      EditionCorpus::EVERGREEN, EditionCorpus::TEASER, EditionCorpus::CONFIRMATION
    )
  end

  it "gives every item but the confirmation a story to belong to" do
    unplaced = EditionCorpus.items.reject { |item| item.story || item.confirmation? }

    expect(unplaced).to be_empty
  end

  it "gives every story at least one newsletter to have been written from" do
    unsourced = EditionCorpus.stories.reject { |story| EditionCorpus.sources(story).any? }

    expect(unsourced).to be_empty
  end

  # The expectations are only checkable if the sections they name are sections
  # an edition can actually file a story in.
  it "files every story in a section the schema allows" do
    sections = EditionCorpus.stories.map(&:section)

    expect(sections - Edition::Story::SECTIONS).to be_empty
  end

  # What this proves and what it does not.
  #
  # It proves the plumbing: that a corpus of realistic bodies survives
  # extraction, quoting and the window query; that an answer shaped the way the
  # schema asks becomes an edition whose stories, sections and citations are
  # the ones the answer named; and that the completeness check passes over a
  # window with a held confirmation in it.
  #
  # It proves nothing whatever about clustering. The fake's answer is the
  # corpus's own ground truth, so what is under test is composition, not
  # judgement: a real model reading these seven bodies might file the tutorial
  # in Briefly, split the one event into three stories, or write up the teaser
  # as though it had read the paywalled half, and every example here would
  # still pass. That question is Milestone 0's, answered by hand off the
  # backtest task with a real key.
  describe "an edition composed from it" do
    # The ground truth as the model would have sent it: one story per story the
    # corpus says is there, citing the newsletters the corpus says cover it.
    # Built from the corpus rather than written out again here, so the answer
    # and the expectations cannot drift apart into a spec that passes because
    # both halves were edited to agree.
    def answer(ingested)
      stories = EditionCorpus.stories.map do |story|
        {
          headline: story.headline, body: story.body, section: story.section,
          newsletter_ids: EditionCorpus.sources(story).map { |item| ingested.fetch(item.key).id },
          post_ids: []
        }
      end

      { stories: stories }.to_json
    end

    # Newsletter.content, which is the window's own rule rather than a list of
    # what was just created — so the confirmation is left out by the same query
    # that will leave it out in production.
    # The corpus is seven newsletters and no blog posts: what it exists to pin
    # is the clustering across senders who disagree, and a post is another
    # source of prose rather than another kind of disagreement.
    def compose(ingested)
      Edition::Editor.new(
        build(:edition), mail_only,
        client: FakeAnthropic.new(text: answer(ingested))
      ).compose.reload
    end

    def mail_only
      Edition::Sources.new(newsletters: Newsletter.content.oldest_first.to_a, posts: [])
    end

    def stories_citing(edition, newsletter)
      edition.stories.select { |story| story.newsletters.include?(newsletter) }
    end

    it "collapses the event three senders covered into one story" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:stack_weekly)).length).to eq(1)
    end

    it "cites all three of them on that story" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:stack_weekly)).sole.newsletters)
        .to contain_exactly(
          ingested.fetch(:stack_weekly), ingested.fetch(:kernel_notes),
          ingested.fetch(:substrate)
        )
    end

    it "leads with it" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:stack_weekly)).sole).to be_lead
    end

    it "puts the evergreen tutorial on the reading list" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(edition.reading_list.sole.newsletters).to eq([ ingested.fetch(:whiteboard) ])
    end

    it "files the paywalled teaser in Briefly" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:margin_notes)).sole).to be_briefly
    end

    # The teaser's mark is the sentence, not a column: nothing in the schema
    # records an item's nature, so "reported as a teaser" means the entry says
    # where the free portion stopped.
    it "says in the teaser's entry that the rest is paywalled" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:margin_notes)).sole.body)
        .to include("paywalled")
    end

    it "files the story only one newsletter covered in Briefly" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(stories_citing(edition, ingested.fetch(:query_plan)).sole).to be_briefly
    end

    it "cites every newsletter the window held" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(edition.stories.flat_map(&:newsletters).uniq)
        .to match_array(Newsletter.content.to_a)
    end

    it "never cites the confirmation" do
      ingested = EditionCorpus.ingest

      edition = compose(ingested)

      expect(edition.stories.flat_map(&:newsletters))
        .not_to include(ingested.fetch(:whiteboard_confirmation))
    end

    # The confirmation is not merely uncited: it is never shown to the editor
    # at all, so there is nothing for a model to write up however it reads it.
    it "never shows the editor the confirmation" do
      ingested = EditionCorpus.ingest

      quoted = Edition::Prompt.new(mail_only).message

      expect(quoted).not_to include(ingested.fetch(:whiteboard_confirmation).subject)
    end
  end
end
