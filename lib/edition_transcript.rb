# An edition printed for reading in a terminal, which is how Milestone 0's
# judgement gets made: composed from a real window, dumped, and read by hand
# against the five checks in the PRD — clustering, attribution, coverage,
# selection, classification.
#
# So the format is not decoration. Every part of it exists to make one of
# those checks possible without opening the database:
#
# - the masthead carries the window and the cost, because the first question
#   about a bad edition is what it was composed from and the second is what
#   iterating on the prompt is going to cost;
# - each story carries its citations by id, publisher and title, because
#   attribution is checked by reading the story against the source it names,
#   and the id is what to grep the stored raw response for;
# - the sources list at the end covers what reading the edition cannot: which
#   sources it was written from and which of them earned only a line.
#
# A citation's id carries a letter — [N4] for mail, [P4] for a post — because
# the two are separate sequences and the raw response keeps them in separate
# lists. Without it a bare [4] names two different things and grepping for it
# finds the wrong one.
#
# The three sections print in the order the page will render them, and the
# reading list disappears when it is empty for the same reason the page's does.
#
# Uppercase for the furniture and sentence case for the editor's own words,
# after docs/siftbox-redesign.md: JetBrains Mono is always uppercase, Archivo
# never is. Two rule weights and nothing between them.
class EditionTranscript
  # A comfortable measure rather than the terminal's width, which would reflow
  # the same edition differently on two machines and make two readings of it
  # hard to compare.
  WIDTH = 72

  HEAVY_RULE = ("═" * WIDTH).freeze
  RULE = ("─" * WIDTH).freeze

  INDENT = "   ".freeze

  # In the order the edition reads, which is also the order the page renders.
  HEADINGS = {
    Edition::Story::LEAD => "LEAD STORIES",
    Edition::Story::BRIEFLY => "BRIEFLY",
    Edition::Story::READING_LIST => "THE READING LIST"
  }.freeze

  # Dollars per token: claude-opus-5 is $5 per million in and $25 per million
  # out. Printed on every edition because the cost of the whole exercise is
  # decided by how many times the prompt gets iterated, and a number on each
  # run is the only place that adds up.
  INPUT_COST = 5.0 / 1_000_000
  OUTPUT_COST = 25.0 / 1_000_000

  def initialize(edition, sources)
    @edition = edition
    @sources = sources
  end

  def text
    (masthead + sections + inventory).join("\n")
  end

  private

  attr_reader :edition, :sources

  def masthead
    [ HEAVY_RULE, number, window, provenance, HEAVY_RULE ]
  end

  # %e pads a single-digit day with a space, which is right in a fixed column
  # and wrong in the middle of a sentence.
  def number
    "NO. #{edition.number} · #{edition.published_on.strftime("%A %e %B").squish.upcase}"
  end

  # Counted apart because they are read apart: a morning of twenty newsletters
  # and one post is a different edition from the other way round, and what
  # went in is the first thing a judgement about the copy below needs.
  def window
    "WINDOW #{stamp(edition.window_started_at)} → #{stamp(edition.window_ended_at)} " \
      "· #{sources.newsletters.length} NEWSLETTERS · #{sources.posts.length} POSTS"
  end

  def stamp(time)
    time.strftime("%e %b %H:%M").squish.upcase
  end

  def provenance
    "#{edition.editor_model.upcase} · PROMPT #{edition.prompt_version} · " \
      "#{tokens(edition.input_tokens)} IN · #{tokens(edition.output_tokens)} OUT · #{cost}"
  end

  def tokens(count)
    ActiveSupport::NumberHelper.number_to_delimited(count)
  end

  def cost
    format("$%.2f", edition.input_tokens * INPUT_COST + edition.output_tokens * OUTPUT_COST)
  end

  def sections
    HEADINGS.flat_map { |section, heading| section(section, heading) }
  end

  # Sifted in Ruby off the one loaded association rather than asked for three
  # times, the way Edition's own section readers do it.
  def section(name, heading)
    stories = edition.stories.select { |story| story.section == name }
    return [] if stories.empty?

    [ "", heading, RULE ] + stories.flat_map { |story| entry(story) }
  end

  def entry(story)
    [ "", headline(story), "" ] + copy(story.body) + [ "" ] + cited(story)
  end

  # Block by block rather than over the whole body, because #folded joins on
  # whitespace and the blank line between two paragraphs is whitespace: run
  # over a body in one go it closes every gap the editor wrote. The gap is
  # put back between blocks here, and dropped in front of the first.
  def copy(body)
    blocks = Edition::Story::Body.new(body).blocks

    blocks.flat_map { |block| [ "" ] + set(block) }.drop(1)
  end

  # A list is written out with its markers, which is the one place they are:
  # the page draws them in CSS instead, and a terminal has no CSS.
  def set(block)
    block.lines.flat_map { |line| folded(line) }
  end

  # The position, because it is the edition's own numbering and it runs across
  # the sections rather than restarting in each — so a story can be talked
  # about by number afterwards.
  def headline(story)
    "#{story.position.to_s.ljust(INDENT.length)}#{story.headline}".truncate(WIDTH)
  end

  # Each association is already typed, so no line here has to ask what it is
  # holding — the two lists are built from the two ends and concatenated.
  def cited(story)
    mail_lines(story.newsletters) { |newsletter| newsletter.subject } +
      post_lines(story.blog_posts) { |post| post.title }
  end

  # Coverage, which is the one check that cannot be made by reading the
  # edition: a source cited by nothing leaves no trace in the copy above.
  # Composition refuses to publish an edition in that state, so a zero here is
  # either a hand-built edition or a guarantee that has stopped holding — both
  # worth seeing rather than hiding. It covers both kinds because the
  # guarantee does.
  def inventory
    lines = mail_lines(sources.newsletters) { |newsletter| coverage(newsletter) } +
      post_lines(sources.posts) { |post| coverage(post) }

    [ "", "SOURCES", RULE, "" ] + lines + [ "" ]
  end

  def mail_lines(newsletters)
    newsletters.map { |newsletter| line("N#{newsletter.id}", newsletter.sender_name, yield(newsletter)) }
  end

  def post_lines(posts)
    posts.map { |post| line("P#{post.id}", post.blog.name, yield(post)) }
  end

  def line(tag, name, tail)
    "#{INDENT}[#{tag}] #{name} — #{tail}".truncate(WIDTH)
  end

  def coverage(source)
    count = citations.fetch(source, 0)
    return "cited by no story" if count.zero?

    "cited by #{count} #{"story".pluralize(count)}"
  end

  # Keyed by the record rather than by its id: two instances of one row are ==
  # and hash alike in Active Record, so the window's sources find themselves
  # here without either side being reloaded — and a Newsletter never collides
  # with a Blog::Post of the same id, because both are keyed on the class too.
  def citations
    @_citations ||= edition.stories
      .flat_map { |story| story.newsletters + story.blog_posts }.tally
  end

  # One line of copy, wrapped to the measure and indented to the page.
  def folded(line)
    laid_out(line, hanging(line))
  end

  # How far a wrapped line's continuation hangs. A list item's hangs under
  # its own first word rather than under its marker: folded flush, the second
  # line of a long item is a line of prose with nothing marking it as part of
  # the item above, and telling those apart is what this transcript is for.
  def hanging(line)
    marker = Edition::Story::Body::BULLET
    return 0 unless line.start_with?(marker)

    marker.length
  end

  def laid_out(line, hang)
    first, *rest = wrapped(line, hang)

    [ indented(first, 0) ] + rest.map { |part| indented(part, hang) }
  end

  def indented(part, hang)
    "#{INDENT}#{" " * hang}#{part}".rstrip
  end

  # Wrapped at the hung measure throughout, so the widest line an item can
  # produce still sits inside the page. A word longer than the measure is
  # left to run past it rather than broken: this is the editor's copy quoted
  # for judgement, and half a word is a word it did not write. Ordinary prose
  # never reaches that case.
  def wrapped(line, hang)
    line.gsub(/(.{1,#{WIDTH - INDENT.length - hang}})(\s+|\z)/, "\\1\n")
      .lines.map(&:chomp)
  end
end
