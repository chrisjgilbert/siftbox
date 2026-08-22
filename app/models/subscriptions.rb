# The index view's collection: the pen and the two nets around it.
#
# Named for the page rather than for the pen, deliberately and after the PRD:
# only the first section is the pen, and silencing lands here later as a
# Sources section, which makes this the roster's front door and back door in
# one place. One word — subscriptions — runs from the URL to the controller to
# here.
#
# Three sections, each closing a different way a subscription can fail
# silently. Held mail is the flag working; new senders is the net for a
# confirmation the phrase set missed and for one that never arrived; recently
# bounced is the only sight there is of mail the spam gate refused before a
# newsletter row ever existed.
#
# Every section is drawn whether or not it has anything in it, against
# Edition::Presenter, which leaves an empty section out. An edition with no
# reading list has nothing to say about the reading list; a pen with nothing
# in it has something to say — that nothing is waiting — and the two sections
# a reader checks after subscribing are the ones most often empty. A section
# that vanishes reads as a broken page, and "recently bounced" that only
# appears when it is non-empty is not the audit surface it exists to be.
#
# Not scoped to a user, the way Feed is not: one inbound address and one
# account, so the authentication gate is the scope.
class Subscriptions
  # "The last couple of weeks", per the PRD. New senders are rare, deliberate
  # events, so the list stays short enough to read at a glance — and unbounded
  # it would be every address there has ever been.
  NEW_SENDER_WINDOW = 14.days

  # One section as the page draws it, with the line to print when it holds
  # nothing. The name is on the wrapper so the type scale can hang off it in
  # CSS without a template asking which section it is drawing.
  Section = Struct.new(:name, :heading, :rows, :empty) do
    def any?
      rows.any?
    end
  end

  # The blog the add-a-feed form is filling in. A fresh one on an ordinary
  # visit; the one that was just refused when BlogsController re-renders this
  # page, so the reader sees what they typed and why it was turned down.
  attr_reader :blog

  def initialize(blog: Blog.new)
    @blog = blog
  end

  # Memoised because the view asks each section twice — whether to draw rows
  # or the empty line, and then for the rows.
  def sections
    @_sections ||= [ awaiting, new_senders, bounced ]
  end

  # The roster, newest first so a blog just added is at the top where the
  # reader is looking. Ordered on the id rather than on created_at, which the
  # table does not carry an index for and which ties on a seeded roster.
  #
  # The counts come from one grouped query rather than from each row asking.
  # Not includes(:posts) either, which is the obvious fix and the wrong one:
  # it would read every body_html — tens of kilobytes each, two hundred rows
  # for one blog — into memory to print "200 posts".
  def blogs
    @_blogs ||= Blog.order(id: :desc).map { |blog| Blog::Row.new(blog, stored.fetch(blog.id, 0)) }
  end

  private

  def stored
    @_stored ||= Blog::Post.group(:blog_id).count
  end

  def awaiting
    section("awaiting", rows(Newsletter.held), empty("awaiting"))
  end

  def new_senders
    section("new_senders", rows(first_mail),
      empty("new_senders", days: NEW_SENDER_WINDOW.in_days.to_i))
  end

  def bounced
    section("bounced", Subscriptions::Bounce.recent,
      empty("bounced", days: Subscriptions::Bounce.retention_days))
  end

  def section(name, rows, empty)
    Section.new(name, I18n.t("subscriptions.index.#{name}.heading"), rows, empty)
  end

  def empty(name, **arguments)
    I18n.t("subscriptions.index.#{name}.empty", **arguments)
  end

  # Deliberately not narrowed to content or to unflagged mail: this is the net
  # for a confirmation the phrase set missed, so a sender whose only mail is
  # sitting in the pen is precisely the sender to show. A held confirmation
  # from a first-time sender therefore appears in both of the first two
  # sections, which is what the PRD's "flagged or not" asks for.
  def first_mail
    Newsletter.first_from_sender.where(received_at: NEW_SENDER_WINDOW.ago..)
  end

  def rows(newsletters)
    newsletters.for_pen.newest_first.map { |newsletter| Subscriptions::Row.new(newsletter) }
  end
end
