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
  # subscriptions_url rather than a host written down: fired from a blog,
  # nothing in the reader's browser knows where siftbox lives.
  def follow_bookmarklet
    "javascript:window.open('#{subscriptions_url}?feed_url='" \
      "+encodeURIComponent(location.href)+'#blogs')"
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
end
