# The sender's HTML exactly as it arrived, for the sandboxed iframe on the
# "View original" screen.
#
# `render plain:` with an HTML content type, rather than a template: it puts
# the stored markup on the wire without calling `html_safe` on reader-supplied
# content. See .claude/rules/security.md.
class Newsletters::SourcesController < ApplicationController
  POLICY = [
    "default-src 'none'",
    # 'self' covers the inline images rewritten to /rails/active_storage
    # paths, which resolve over http in development and so match neither
    # https: nor data:.
    "img-src 'self' https: data:",
    "style-src 'unsafe-inline'",
    "font-src https:",
    "form-action 'none'",
    "frame-ancestors 'self'",
    "base-uri 'none'",
    # The iframe tag's sandbox only applies when the page is framed. Opening
    # this URL directly — "open frame in new tab", a bookmark — would
    # otherwise serve sender-designed HTML from this app's own origin.
    "sandbox allow-popups allow-popups-to-escape-sandbox"
  ].join("; ").freeze

  def show
    newsletter = Newsletter.find(params[:newsletter_id])

    response.set_header("Content-Security-Policy", POLICY)
    render plain: newsletter.body_html, content_type: "text/html"
  end
end
