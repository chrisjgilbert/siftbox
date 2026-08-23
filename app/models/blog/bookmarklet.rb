# The line a reader keeps in their bookmarks bar to follow the blog they are
# reading. Dragged off the Settings page, fired from somebody else's site, it
# opens the follow form with that page's address already in it.
#
# It navigates rather than posting, and that is the whole design. This app's
# session cookie is SameSite=Lax, so a cross-site POST would arrive with no
# cookie and no CSRF token — and making one work would mean a token endpoint
# or wider CORS on the one endpoint here that dials out on a reader's say-so.
# Lax does send the cookie on a top-level navigation, so the reader lands
# signed in and follows through an ordinary first-party form, and the bookmark
# holds nothing about them.
#
# An object rather than a helper because none of this is formatting, which is
# what .claude/rules/views.md keeps helpers for. App chrome as a domain object,
# the way Subscriptions::Badge is, and reaching the router the same way.
class Blog::Bookmarklet
  # The query SubscriptionsController#index reads, and the section id
  # app/views/blogs/_section.html.erb declares.
  #
  # Named here because a bookmarklet is the one thing this app ships that
  # outlives a deploy: every copy already sitting in a bookmarks bar is a
  # string nobody can reissue. Rename either of these without the other and
  # they all quietly stop working, so both are pinned by examples that read
  # them from here and ask the real page.
  ANCHOR = "blogs"
  PARAMETER = "feed_url"

  # noopener because the tab it opens would otherwise keep a live reference
  # back to the blog, and a third-party script there can steer a tab it holds
  # — at a sign-in form on what the reader takes for a tab they opened.
  #
  # The anchor rather than focusing the field on arrival: the section is the
  # last thing on a long page and needs the scroll, but a filled field with
  # the cursor already in it is a follow one keystroke away for any page that
  # can link a signed-in reader here.
  def href
    "javascript:window.open('#{address}?#{PARAMETER}='" \
      "+encodeURIComponent(location.href)+'##{ANCHOR}','_blank','noopener')"
  end

  private

  # Where this app answers, rather than where the request that drew the page
  # came in. A bookmark outlives the request that made it, so recording
  # whichever Host header happened to arrive — and config.hosts is not set, so
  # that is any of them — pins it to the host it was dragged from.
  #
  # These are the options the app already keeps for links in mail, which want
  # the canonical host for the same reason. Borrowed rather than duplicated;
  # the day mail needs a sending domain of its own, this needs its own setting.
  def address
    Rails.application.routes.url_helpers
      .subscriptions_url(**Rails.configuration.action_mailer.default_url_options)
  end
end
