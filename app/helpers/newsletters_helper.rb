module NewslettersHelper
  # `sanitize` returns a safe buffer, which is why no view calls `html_safe`
  # on newsletter markup. See .claude/rules/security.md.
  #
  # Takes the presenter's body rather than building one here. The presenter
  # owns the parse, so the image it promotes above the article is already out
  # of this, and the stored sizes are already on what is left.
  def newsletter_body(newsletter)
    sanitize newsletter.body,
      tags: Newsletter::Body::TAGS,
      attributes: Newsletter::Body::ATTRIBUTES
  end
end
