# Display logic for one newsletter, built by whatever is listing it, so no
# template has to format a timestamp or assemble a sender line.
#
# The PRD retires this along with the reader ("the presenter goes"), and most
# of it did: the article body, the promoted image, the kicker, the issue
# number, the reading time and the previous/next links went with the page they
# were written for. What is left is here because three surviving screens ask
# it the same two questions — the archive's rows, the Subscriptions page, and
# a story's citations all need a sender line that survives mail with no From
# header, and the archive needs the timestamp beside it. Deleting the class
# outright would have copied #sender into three places.
class Newsletter::Presenter
  delegate :held?, :lead_image?, :lead_image_url, :snippet, :subject,
    :to_param, to: :newsletter

  def initialize(newsletter)
    @newsletter = newsletter
  end

  # Mail with no From header at all leaves nothing to show, and a row headed
  # by a bare em dash reads as a rendering fault rather than as missing data.
  def sender
    newsletter.sender_name.presence || newsletter.sender_email.presence ||
      I18n.t("newsletters.unknown_sender")
  end

  # Where the row goes, and whether following it leaves the app. A newsletter
  # opens its own stored original in the sandboxed frame; a post opens the
  # blog. The template asks rather than deciding, so it never has to know
  # which kind of thing it is drawing.
  def path
    routes.newsletter_original_path(newsletter)
  end

  # Nothing, because the link stays here. The template spreads whatever it is
  # given rather than asking which kind of row it is drawing.
  def link_attributes
    {}
  end

  # What the mono line says after the sender. Nothing, for mail: newsletters
  # are twenty a day against three posts, so marking the common case would put
  # a word on every row of the archive to say the usual thing.
  def kind
    nil
  end

  def timestamp
    age.timestamp
  end

  # What a row with no image says in the space one would have taken. Asked
  # rather than named in the template, because the sentence differs: a post
  # was never in an email and saying so about one is simply wrong.
  def no_image
    I18n.t("newsletters.index.no_image")
  end

  # Where an original's top bar goes back to. The archive for content, and the
  # pen for anything the archive would refuse to list: Newsletter.content
  # excludes dismissed mail, which is still reachable because the
  # Subscriptions page's new-senders list is deliberately not content-scoped.
  # Sending it to the archive would be a way back to a page without it.
  def back_path
    return routes.subscriptions_path if newsletter.dismissed?

    routes.newsletters_path
  end

  # Named for where it goes, so the label cannot say "archive" over a link to
  # the pen. Shares the pen bar's key rather than repeating its wording.
  def back_label
    return I18n.t("newsletters.original.pen.back") if newsletter.dismissed?

    I18n.t("newsletters.original.back")
  end

  private

  attr_reader :newsletter

  def age
    Newsletter::Age.new(newsletter.received_at)
  end

  # A presenter has no route helpers of its own, the way
  # Edition::Story::Presenter has none either.
  def routes
    Rails.application.routes.url_helpers
  end
end
