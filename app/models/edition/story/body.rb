# The editor's copy, read as the blocks it was written in: a paragraph per
# paragraph, and a list where the editor wrote one.
#
# The copy is stored as plain text and stays plain text — nothing here builds
# markup out of what a model wrote, and nothing downstream is allowed to. The
# blocks carry the editor's words as strings, the page renders each through
# ordinary escaping, and the only thing this class decides is where one block
# stops and the next begins. See .claude/rules/security.md.
#
# Before this, a story was one paragraph however long it ran, because the page
# drew the whole body in a single element with `white-space: pre-line` and the
# prompt asked for prose with no structure in it. A lead written off six
# newsletters is six hundred words, and on a phone that is a column of text a
# reader scrolls past rather than reads.
class Edition::Story::Body
  # What separates one paragraph from the next: a blank line, which is what
  # the instructions ask for. A single newline inside a paragraph is read as
  # a wrap and closed up, because that is the cheaper mistake — a model that
  # hard-wraps its prose would otherwise arrive as a column of one-line
  # paragraphs, where a model that separates paragraphs with a single newline
  # arrives as one paragraph, which is what the page drew before this.
  BREAK = /\n[ \t]*\n/

  # What opens a list item: the hyphen the instructions ask for, and the two
  # characters a model reaches for instead. The space after it is part of the
  # marker, so a line that is only a hyphen stays prose.
  #
  # The en and em dashes are deliberately not here. They are punctuation this
  # copy genuinely uses, and a sentence that opens on one — a continuation,
  # an aside — would otherwise be read as the first item of a list nobody
  # wrote.
  MARKER = /\A[-*•]\s+/

  # How a list item is written back out in plain text. The page never uses
  # it: the marker there is drawn in CSS, as a mono counter, so the copy on
  # screen carries no punctuation the editor did not write.
  BULLET = "-".freeze

  # The two shapes, as two classes rather than one class with a flag, so that
  # nothing that draws a block has to ask what kind it is holding. Both answer
  # #name, which is the partial the page renders them with, and #lines, which
  # is the plain text the terminal transcript folds.
  Paragraph = Struct.new(:text) do
    def name
      "paragraph"
    end

    def lines
      [ text ]
    end
  end

  Bullets = Struct.new(:items) do
    def name
      "bullets"
    end

    def lines
      items.map { |item| "#{BULLET} #{item}" }
    end
  end

  def initialize(text)
    @text = text
  end

  # Memoised because the page asks once per story and the transcript asks
  # again for the same rows.
  def blocks
    @_blocks ||= groups.flat_map { |group| blocks_in(group) }
  end

  private

  attr_reader :text

  # The blank lines go, so a break is one break however many newlines the
  # editor left there, and a body that is nothing but whitespace reads as no
  # blocks at all rather than as an empty one.
  def groups
    text.to_s.split(BREAK).map { |group| lines_in(group) }.reject(&:empty?)
  end

  def lines_in(group)
    group.lines.map(&:strip).reject(&:blank?)
  end

  # A list needs no blank line around it, because its marker is what starts
  # it: consecutive marked lines are one list, and the unmarked lines either
  # side are the paragraphs it sits between. chunk rather than chunk_while,
  # because what separates the runs is a property of each line rather than of
  # each pair.
  def blocks_in(group)
    group.chunk { |line| marked?(line) }.map { |marked, run| block(marked, run) }
  end

  def block(marked, run)
    return Bullets.new(run.map { |line| item(line) }) if marked

    Paragraph.new(run.join(" "))
  end

  def marked?(line)
    MARKER.match?(line)
  end

  def item(line)
    line.sub(MARKER, "")
  end
end
