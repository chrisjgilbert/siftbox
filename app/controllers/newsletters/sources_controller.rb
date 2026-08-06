# The sender's HTML exactly as it arrived, for the sandboxed iframe on the
# "View original" screen.
#
# `render plain:` with an HTML content type, rather than a template: it puts
# the stored markup on the wire without calling `html_safe` on reader-supplied
# content. See .claude/rules/security.md.
class Newsletters::SourcesController < ApplicationController
  POLICY = [
    "default-src 'none'",
    "img-src https: data:",
    "style-src 'unsafe-inline'",
    "font-src https:",
    "form-action 'none'",
    "frame-ancestors 'self'"
  ].join("; ").freeze

  def show
    newsletter = Newsletter.find(params[:newsletter_id])

    response.set_header("Content-Security-Policy", POLICY)
    response.set_header("X-Content-Type-Options", "nosniff")
    render plain: newsletter.body_html, content_type: "text/html"
  end
end
