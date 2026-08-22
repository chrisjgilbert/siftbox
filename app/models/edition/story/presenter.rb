# Display logic for one story: the editor's words, and the sources they can be
# checked against.
#
# The words go through untouched and unescaped-by-nothing — the template
# renders them with ordinary ERB escaping, and there is no html_safe path
# anywhere on this class. An edition is written by a model out of mail written
# by strangers; see .claude/rules/security.md.
class Edition::Story::Presenter
  # One citation as the page draws it: who said it, where the reader goes to
  # read what they actually said, and how that link opens. The attributes are
  # what separates the two kinds — a newsletter's original is served by this
  # app in a sandboxed frame and stays in the tab, where a post lives on
  # somebody else's site.
  Source = Struct.new(:sender, :path, :attributes)

  delegate :body, :headline, to: :story

  def initialize(story)
    @story = story
  end

  # The headline column defaults to "", and a Briefly line is short enough
  # that the editor can leave it there. The page draws no heading over an
  # empty string.
  def headline?
    headline.present?
  end

  # The link every claim carries. Its destination is the original — the
  # sender's own HTML in the sandboxed frame — because the edition is the app's
  # words and the only honest way to check them is the mail itself.
  #
  # Mail first, then posts. Any total order would do — this is the order the
  # prompt quotes them in, and it keeps a story's citations from reordering
  # between two loads of the same page.
  #
  # Memoised because the page asks three times per story — whether there are
  # any, what to call them, and then for each one.
  def sources
    @_sources ||= cited_mail + cited_posts
  end

  def cited?
    sources.any?
  end

  # "Source" over one name and "Sources" over three. The line is furniture:
  # without it a row of sender names under a paragraph is only a row of names.
  def sources_label
    I18n.t("editions.story.sources", count: sources.length)
  end

  private

  attr_reader :story

  # Through each record's own feed presenter, so a citation reads the way the
  # archive row for the same thing reads: mail with no From header at all
  # says "Unknown sender" here too, and a post with no address falls back to
  # its blog rather than citing an empty href.
  def cited_mail
    story.newsletters.map do |newsletter|
      presenter = Newsletter::Presenter.new(newsletter)

      Source.new(presenter.sender, presenter.path, {})
    end
  end

  def cited_posts
    story.blog_posts.map do |post|
      presenter = Blog::Post::Presenter.new(post)

      Source.new(presenter.sender, presenter.path, presenter.link_attributes)
    end
  end
end
