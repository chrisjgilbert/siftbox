require "rails_helper"

RSpec.describe Edition::Editor do
  # The answer the model would have sent, in the shape Edition::Prompt's schema
  # asks for. Written out here rather than through a factory because it is not
  # a record — it is the one thing this class is built to distrust, and a spec
  # that could not write a bad one could not test the checking.
  def answer(*stories)
    { stories: stories }.to_json
  end

  def story(cites: [], posts: [], section: "lead", headline: "Figma filed", body: "The S-1 landed.")
    {
      headline: headline, body: body, section: section,
      newsletter_ids: cites, post_ids: posts
    }
  end

  # Persisted rather than built: citations carry a foreign key to newsletters,
  # so a composition against stubbed newsletters would fail on the constraint
  # rather than on anything this class did.
  def newsletter(subject: "Money Stuff")
    create(:newsletter, subject: subject)
  end

  def compose(newsletters, client, posts: [])
    sources = Edition::Sources.new(newsletters: newsletters, posts: posts)

    Edition::Editor.new(build(:edition), sources, client: client).compose
  end

  # Persisted for the same reason the newsletters are: a citation carries a
  # real foreign key to blog_posts.
  def post(title: "Rewriting the planner")
    create(:blog_post, title: title)
  end

  it "writes a story for each one the model answered" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(
      story(cites: [ source.id ], headline: "Figma filed"),
      story(cites: [ source.id ], headline: "Rates held")
    ))

    compose([ source ], client)

    expect(Edition.last.stories.map(&:headline)).to eq([ "Figma filed", "Rates held" ])
  end

  it "writes each story's body as the model wrote it" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], body: "Levine read the filing."))
    )

    compose([ source ], client)

    expect(Edition.last.stories.map(&:body)).to eq([ "Levine read the filing." ])
  end

  it "files a lead story in the leads" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ], section: "lead")))

    edition = compose([ source ], client)

    expect(edition.reload.lead_stories.map(&:headline)).to eq([ "Figma filed" ])
  end

  it "files a briefly line in Briefly" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], section: "briefly", headline: "Rates held"))
    )

    edition = compose([ source ], client)

    expect(edition.reload.briefly.map(&:headline)).to eq([ "Rates held" ])
  end

  it "files an evergreen item on the reading list" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ], section: "reading_list", headline: "Consensus"))
    )

    edition = compose([ source ], client)

    expect(edition.reload.reading_list.map(&:headline)).to eq([ "Consensus" ])
  end

  # The model decides what order an edition reads in, across the sections as
  # well as within them, and the position column is where that order is kept.
  it "numbers the stories in the order the model answered them" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(
      story(cites: [ source.id ], section: "briefly"),
      story(cites: [ source.id ], section: "lead")
    ))

    compose([ source ], client)

    expect(Edition.last.stories.map(&:position)).to eq([ 1, 2 ])
  end

  it "cites the newsletters a story was written from" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id, diff.id ])))

    compose([ levine, diff ], client)

    expect(Edition.last.stories.first.newsletters).to contain_exactly(levine, diff)
  end

  # An answer naming one source twice is a duplicate, not a mistake about what
  # the story was written from — Edition::Story refuses to save it, so it is
  # taken down to one here rather than costing the day its edition.
  it "cites a newsletter once when the model named it twice" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id, source.id ])))

    compose([ source ], client)

    expect(Edition.last.stories.first.newsletters).to eq([ source ])
  end

  it "records the model that wrote the edition and the prompt it was given" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    compose([ source ], client)

    expect(Edition.last.editor_model).to eq("claude-opus-5")
    expect(Edition.last.prompt_version).to eq(Edition::Prompt::VERSION)
  end

  it "records what the edition cost" do
    source = newsletter
    client = FakeAnthropic.new(
      text: answer(story(cites: [ source.id ])), input_tokens: 61_000, output_tokens: 7_400
    )

    compose([ source ], client)

    expect(Edition.last.input_tokens).to eq(61_000)
    expect(Edition.last.output_tokens).to eq(7_400)
  end

  # Enough to read a bad edition back and to write it again after a prompt
  # change without asking every newsletter for its body a second time.
  it "keeps the whole answer for reading back later" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    compose([ source ], client)

    expect(Edition.last.raw_response).to include("Figma filed")
  end

  it "publishes the edition it was given" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    edition = compose([ source ], client)

    expect(edition).to be_persisted
  end

  it "asks once when the first answer covers the window" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ])))

    compose([ source ], client)

    expect(client.messages.requests.length).to eq(1)
  end

  it "asks again when the answer left a newsletter uncited" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: [
      answer(story(cites: [ levine.id ])),
      answer(story(cites: [ levine.id, diff.id ]))
    ])

    compose([ levine, diff ], client)

    expect(client.messages.requests.length).to eq(2)
  end

  it "publishes the regenerated edition rather than the incomplete one" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: [
      answer(story(cites: [ levine.id ])),
      answer(story(cites: [ levine.id, diff.id ]))
    ])

    compose([ levine, diff ], client)

    expect(Edition.last.stories.first.newsletters).to contain_exactly(levine, diff)
  end

  it "gives up on an answer that never covers the window" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id ])))

    expect { compose([ levine, diff ], client) }
      .to raise_error(Edition::Editor::Incomplete, /no story cited newsletter #{diff.id}\b/)
  end

  it "stops asking after the attempts it is allowed" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id ])))

    suppress(Edition::Editor::Incomplete) { compose([ levine, diff ], client) }

    expect(client.messages.requests.length).to eq(Edition::Editor::ATTEMPTS)
  end

  # The whole point of failing loudly: half an edition, published, would read
  # as a complete one, and the newsletter it dropped has no other surface left
  # to be found on.
  it "leaves no edition behind when it gives up" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id ])))

    suppress(Edition::Editor::Incomplete) { compose([ levine, diff ], client) }

    expect(Edition.count).to eq(0)
  end

  # A background job's exception says composition failed and nothing about
  # what was wrong with it, so this line is the entire diagnosis.
  it "logs which newsletter went missing when it gives up" do
    levine = newsletter(subject: "Money Stuff")
    diff = newsletter(subject: "The Diff")
    client = FakeAnthropic.new(text: answer(story(cites: [ levine.id ])))
    allow(Rails.logger).to receive(:error)

    suppress(Edition::Editor::Incomplete) { compose([ levine, diff ], client) }

    expect(Rails.logger).to have_received(:error).with(/no story cited newsletter #{diff.id}\b/)
  end

  it "asks again when the answer cited a newsletter that was not in the window" do
    source = newsletter
    client = FakeAnthropic.new(text: [
      answer(story(cites: [ source.id, source.id + 404 ])),
      answer(story(cites: [ source.id ]))
    ])

    compose([ source ], client)

    expect(Edition.last.stories.first.newsletters).to eq([ source ])
  end

  it "gives up rather than citing a newsletter that was not in the window" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id, source.id + 404 ])))

    expect { compose([ source ], client) }.to raise_error(
      Edition::Editor::Incomplete, /cited newsletter #{source.id + 404}, which was not in the window/
    )
  end

  # The graph is saved in one go, so a story the database or the model layer
  # refuses takes the edition down with it rather than leaving a masthead with
  # nothing under it.
  it "leaves no edition behind when a story will not save" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(story(cites: [ source.id ], body: "")))

    suppress(ActiveRecord::RecordInvalid) { compose([ source ], client) }

    expect(Edition.count).to eq(0)
  end

  it "cites the post a story was written from" do
    source = post
    client = FakeAnthropic.new(text: answer(story(posts: [ source.id ])))

    edition = compose([], client, posts: [ source ])

    expect(edition.reload.stories.sole.blog_posts).to eq([ source ])
  end

  it "cites a newsletter and a post in one story" do
    mail = newsletter
    written = post
    client = FakeAnthropic.new(
      text: answer(story(cites: [ mail.id ], posts: [ written.id ]))
    )

    edition = compose([ mail ], client, posts: [ written ])

    expect(edition.reload.stories.sole.newsletters).to eq([ mail ])
    expect(edition.reload.stories.sole.blog_posts).to eq([ written ])
  end

  # The two id sequences are independent, so a window holding newsletter 7 and
  # post 7 is ordinary rather than contrived. A story citing only one of them
  # must not pick up the other.
  it "keeps a post id from citing the newsletter that shares its number" do
    mail = newsletter
    written = create(:blog_post, id: mail.id)
    client = FakeAnthropic.new(text: answer(
      story(cites: [ mail.id ], headline: "Figma filed"),
      story(posts: [ written.id ], headline: "Rewriting the planner")
    ))

    edition = compose([ mail ], client, posts: [ written ])

    cited = edition.reload.stories.detect { |story| story.headline == "Rewriting the planner" }
    expect(cited.blog_posts).to eq([ written ])
    expect(cited.newsletters).to be_empty
  end

  it "asks again when the answer left a post uncited" do
    covered = post(title: "Rewriting the planner")
    missed = post(title: "The cost of a cache miss")
    client = FakeAnthropic.new(text: [
      answer(story(posts: [ covered.id ])),
      answer(story(posts: [ covered.id, missed.id ]))
    ])

    edition = compose([], client, posts: [ covered, missed ])

    expect(edition.reload.stories.sole.blog_posts).to contain_exactly(covered, missed)
  end

  it "gives up rather than publishing an edition that left a post uncited" do
    covered = post(title: "Rewriting the planner")
    missed = post(title: "The cost of a cache miss")
    client = FakeAnthropic.new(text: answer(story(posts: [ covered.id ])))

    expect { compose([], client, posts: [ covered, missed ]) }
      .to raise_error(Edition::Editor::Incomplete, /no story cited post #{missed.id}\b/)
  end

  it "gives up rather than citing a post that was not in the window" do
    source = post
    client = FakeAnthropic.new(text: answer(story(posts: [ source.id + 404 ])))

    expect { compose([], client, posts: [ source ]) }.to raise_error(
      Edition::Editor::Incomplete, /cited post #{source.id + 404}, which was not in the window/
    )
  end

  # A story naming one post twice is ordinary model output, and
  # Edition::Story refuses it. Costing the day its edition over a duplicate
  # that changes nothing about what was written would be the wrong trade.
  it "cites a post once when the answer named it twice in one story" do
    source = post
    client = FakeAnthropic.new(text: answer(story(posts: [ source.id, source.id ])))

    edition = compose([], client, posts: [ source ])

    expect(edition.reload.stories.sole.blog_posts).to eq([ source ])
  end

  # Every failure at once, so a second run is not needed to discover the rest
  # — which is what the class promises and what a short circuit on the first
  # kind would quietly stop doing.
  it "names a missed newsletter and an invented post in one complaint" do
    mail = newsletter
    missed = newsletter(subject: "The Diff")
    written = post
    client = FakeAnthropic.new(
      text: answer(story(cites: [ mail.id ], posts: [ written.id, written.id + 404 ]))
    )

    expect { compose([ mail, missed ], client, posts: [ written ]) }.to raise_error(
      Edition::Editor::Incomplete,
      /no story cited newsletter #{missed.id}\b.*cited post #{written.id + 404}/m
    )
  end

  # The instructions ask for it, and asking is exactly the part that cannot be
  # verified — which is this class's own argument for checking completeness
  # mechanically. A story citing nothing satisfies both existing checks
  # vacuously: nothing was missed and nothing was invented. It also ships
  # under the masthead with no attribution, which is the one thing an edition
  # is not allowed to do.
  it "gives up rather than publishing a story that cites nothing" do
    source = newsletter
    client = FakeAnthropic.new(text: answer(
      story(cites: [ source.id ], headline: "Figma filed"),
      story(headline: "Something else entirely")
    ))

    expect { compose([ source ], client) }
      .to raise_error(Edition::Editor::Incomplete, /cites no source/)
  end

  it "asks again when one story in the answer cited nothing" do
    source = newsletter
    client = FakeAnthropic.new(text: [
      answer(story(cites: [ source.id ]), story(headline: "Something else entirely")),
      answer(story(cites: [ source.id ]))
    ])

    edition = compose([ source ], client)

    expect(edition.reload.stories.length).to eq(1)
  end
end
