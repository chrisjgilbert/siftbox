# Display logic for one story: the editor's words, and the sources they can be
# checked against.
#
# The words go through untouched and unescaped-by-nothing — the template
# renders them with ordinary ERB escaping, and there is no html_safe path
# anywhere on this class. An edition is written by a model out of mail written
# by strangers; see .claude/rules/security.md.
class Edition::Story::Presenter
  # One citation as the page draws it: who said it, and where the reader goes
  # to read what they actually said.
  Source = Struct.new(:sender, :path)

  delegate :body, :headline, to: :story

  def initialize(story)
    @story = story
  end

  # The link every claim carries. Its destination is the original — the
  # sender's own HTML in the sandboxed frame — because the edition is the app's
  # words and the only honest way to check them is the mail itself.
  def sources
    story.newsletters.map { |newsletter| source(newsletter) }
  end

  private

  attr_reader :story

  # Through Newsletter::Presenter for the name, so mail with no From header at
  # all reads the same here as it does in the archive rather than citing a
  # blank.
  def source(newsletter)
    Source.new(Newsletter::Presenter.new(newsletter).sender, original_path(newsletter))
  end

  # A presenter has no route helpers of its own, the way Newsletter's
  # #inline_image_path has none either.
  def original_path(newsletter)
    Rails.application.routes.url_helpers.newsletter_original_path(newsletter)
  end
end
