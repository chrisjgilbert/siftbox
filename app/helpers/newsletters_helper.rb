module NewslettersHelper
  # `sanitize` returns a safe buffer, which is why no view calls `html_safe`
  # on newsletter markup. See .claude/rules/security.md.
  def newsletter_body(newsletter)
    sanitize Newsletter::Body.new(newsletter.body_html).scrubbed,
      tags: Newsletter::Body::TAGS,
      attributes: Newsletter::Body::ATTRIBUTES
  end
end
