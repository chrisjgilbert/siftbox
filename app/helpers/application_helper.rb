module ApplicationHelper
  # The address subscriptions are pointed at. A helper rather than a reach for
  # Rails.configuration from the template — see .claude/rules/views.md.
  def inbound_address
    Rails.configuration.x.inbound_address
  end

  # Dragged to a bookmarks bar and fired from somebody else's blog: it opens
  # the follow form with the page the reader was standing on already in it.
  #
  # It navigates rather than posting, and that is the whole design. This app's
  # session cookie is SameSite=Lax, so a cross-site POST would arrive with no
  # cookie and no CSRF token — which is a reason to build a token endpoint or
  # widen CORS on the one endpoint here that dials out on a reader's say-so.
  # Lax does send the cookie on a top-level navigation, so the reader lands
  # signed in and follows with an ordinary first-party form. Nothing about
  # them is stored in the bookmark.
  #
  # noopener because the tab it opens would otherwise keep a live reference
  # back to the blog, and a third-party script on that page can steer a tab
  # it holds — at a sign-in form on what the reader believes is a tab they
  # opened themselves.
  #
  # The anchor rather than focusing the field on arrival: the section is the
  # last thing on a long page and needs the scroll, but a filled field with
  # the cursor already in it is a follow one keystroke from any page that can
  # link a signed-in reader here.
  def follow_bookmarklet
    "javascript:window.open('#{canonical_url(subscriptions_path)}?feed_url='" \
      "+encodeURIComponent(location.href)+'#blogs','_blank','noopener')"
  end

  # The mark's stroke weight compensates for size: it thickens as the mark
  # shrinks, so the brackets still read at favicon scale. Set on the <svg>
  # rather than per path, which is what `application/mark` does with this.
  def mark_stroke_width(size)
    return 7 if size <= 16
    return 6 if size <= 22
    return 5 if size <= 30

    4
  end

  private

  # Where this app answers, rather than where this request came in.
  #
  # For the things that outlive the request that made them — a link in an
  # email, a bookmarklet kept in a bookmarks bar. Both are wrong if they
  # record whichever Host header happened to arrive, and config.hosts is not
  # set, so that is any of them. This is the one place the app already writes
  # down where it answers, kept for exactly that reason.
  def canonical_url(path)
    options = Rails.configuration.action_mailer.default_url_options

    root_url(**options).chomp("/") + path
  end
end
