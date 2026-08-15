# The notice the edition page carries while a confirmation is waiting.
#
# App chrome, and never anything else. Its words are a count and a locale
# string; nothing the editor wrote can reach it, and nothing on the page it
# sits above can put anything into it. A story that argued with the reader
# about their subscriptions would be the model's words wearing the app's
# authority — see .claude/rules/security.md on where the model's output is
# allowed to go, which is through ordinary escaping into a story and nowhere
# else.
#
# State rather than a flash, which is the whole point of it. The failure mode
# it closes is a hold nobody actions until the confirm link expires, so it has
# to survive every page load until the mail is resolved: it cannot scroll
# away, cannot be cleared by reading it, and reappears on the next visit
# because it is a question the database answers, not a message that was
# delivered once.
#
# Not scoped to a user, the way Subscriptions and Feed are not: one inbound
# address and one account, so the authentication gate is the scope.
class Subscriptions::Badge
  def pending?
    count.positive?
  end

  # Sentence case here and uppercased in CSS, because JetBrains Mono is always
  # uppercase and the locale file is not the place to shout:
  # docs/siftbox-redesign.md §2. One and three are different sentences and
  # i18n has that built in, so the plural is a translation rather than a
  # conditional in a template.
  def line
    I18n.t("subscriptions.badge.line", count: count)
  end

  def path
    Rails.application.routes.url_helpers.subscriptions_path
  end

  private

  # One COUNT for the two questions the page asks — whether to draw, and what
  # to say — because the edition page is measured and opened every morning.
  # It rides index_newsletters_on_held_at, which is partial on
  # held_at IS NOT NULL and so covers exactly the rows this counts.
  def count
    @_count ||= Newsletter.held.count
  end
end
