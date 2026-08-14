# The editor of one edition: it reads the newsletters it was handed, asks the
# model what the stories are, and writes the answer out as an edition — but
# only once it has checked that the answer accounts for every newsletter it
# was shown.
#
# The window is not computed here and neither is the edition's number. Both
# belong to whoever decides an edition is due, and both are wrong in ways this
# class cannot see: a window has two clauses (mail released out of the
# confirmation pen has a received_at behind the watermark), and the set an
# edition may be composed from is Newsletter.content rather than every
# newsletter there is. This takes the edition and its newsletters as given and
# is answerable for what happens between them.
class Edition::Editor
  # Three answers, not "until it works". A regeneration is a second full
  # request at the same price as the first — the window is not cached, and at
  # a five-minute cache TTL against a once-daily job it could not be — so an
  # unbounded loop against a prompt that has stopped producing complete
  # editions spends the month's budget finding that out. Three is enough for a
  # model that dropped one newsletter by inattention and few enough that a
  # prompt which cannot do it never gets far.
  ATTEMPTS = 3

  # The completeness guarantee failed, and this is the end of the run: no
  # edition today rather than an edition that quietly omits a newsletter the
  # reader will never be told about. Loud on purpose — with the inbox demoted,
  # an uncited newsletter is one the reader has no other surface to find.
  Incomplete = Class.new(StandardError)

  def initialize(edition, newsletters, client: nil)
    @edition = edition
    @newsletters = newsletters
    @client = client
  end

  def compose
    record(accepted)
    edition
  end

  private

  attr_reader :edition, :newsletters, :client

  # The check is mechanical and it is made here, against the ids that went
  # out, rather than asked for in the prompt and hoped for: the instructions
  # do ask, and asking is exactly the part that cannot be verified. An answer
  # that fails is thrown away whole rather than patched up, because a story
  # list missing a source is a list that was clustered without it.
  def accepted
    faults = []

    ATTEMPTS.times do
      copy = draft.write
      faults = faults_in(copy.stories)
      return copy if faults.empty?
    end

    abandon(faults)
  end

  # Both failures at once, so a second run is not needed to discover the
  # second of them. Ids rather than subjects: they are what went to the model
  # and what came back, and they are what to grep the raw response for.
  def faults_in(stories)
    cited = stories.flat_map { |story| story.fetch(:newsletter_ids) }.uniq

    [ uncited(cited), invented(cited) ].compact
  end

  def uncited(cited)
    missed = sources.keys - cited
    return if missed.empty?

    "no story cited newsletter #{missed.join(", ")}"
  end

  # A citation is a promise that the claim beside it can be checked against
  # the mail it names, so an id that was never in the window is a promise
  # about nothing. Dropping it quietly would leave the story standing with the
  # attribution it was written under taken away, which is the worse half of
  # the same failure — the answer goes back instead.
  def invented(cited)
    unknown = cited - sources.keys
    return if unknown.empty?

    "a story cited newsletter #{unknown.join(", ")}, which was not in the window"
  end

  # Logged as well as raised: the raise stops the edition, but a background
  # job's exception says only that composition failed, and which newsletters
  # went missing is the whole diagnosis.
  def abandon(faults)
    complaint = "edition abandoned after #{ATTEMPTS} attempts: #{faults.join("; ")}"
    Rails.logger.error(complaint)

    raise Incomplete, complaint
  end

  # One save! over a graph built in memory, which is one transaction: Rails
  # wraps a save and the associations it autosaves together, so there is no
  # moment at which an edition exists without its stories or a story without
  # its citations. Building it up with create! instead would leave a headless
  # edition behind the first time a story failed to validate.
  def record(copy)
    edition.assign_attributes(provenance(copy))
    copy.stories.each_with_index { |story, index| build(story, index + 1) }

    edition.save!
  end

  def provenance(copy)
    {
      editor_model: copy.model, prompt_version: copy.prompt_version,
      input_tokens: copy.input_tokens, output_tokens: copy.output_tokens,
      raw_response: copy.raw_response
    }
  end

  # Positions run across the whole edition rather than restarting per section,
  # in the order the answer came in. The page splits the sections out again,
  # and each section keeps the order the model put it in.
  #
  # fetch, not [], on every field: the schema requires all four, so a missing
  # one is structured output having stopped being enforced, and a story
  # silently headlined nil is not how that should be found out.
  def build(story, position)
    built = edition.stories.build(
      body: story.fetch(:body), headline: story.fetch(:headline),
      position: position, section: story.fetch(:section)
    )

    cite(built, story.fetch(:newsletter_ids))
  end

  # uniq because Edition::Story validates that a story's citations name
  # distinct newsletters and an answer naming one source twice is perfectly
  # ordinary model output. The validation stays the floor under everything
  # else that builds citations; this keeps a duplicate from costing the day
  # its edition over something that changes nothing about what was written.
  #
  # Cited by object rather than by id: the newsletters are already in memory,
  # and belongs_to would otherwise load each one back out of the database to
  # satisfy its own presence check.
  def cite(story, ids)
    ids.uniq.each { |id| story.citations.build(newsletter: sources.fetch(id)) }
  end

  # The window by id, which is both the set every citation is checked against
  # and where the citations are built from — one index for the two, so what
  # was accepted and what gets written can never be different sets.
  def sources
    @_sources ||= newsletters.index_by(&:id)
  end

  # One draft across every attempt, so each regeneration is another request
  # through the same client rather than another client.
  def draft
    @_draft ||= Edition::Draft.new(Edition::Prompt.new(newsletters), client: client)
  end
end
