# One line of the roster that is a muted sender: what they are called, how
# long it has been like that, and the way back.
#
# The counterpart to Blog::Row, and between them they draw the Sources
# section. They answer the questions the section asks of every row and differ
# in their template, the way the editions archive holds an edition and a gap.
#
# A muted sender has no feed address, no poll state and no stored count — the
# three things a blog's row is mostly made of — so what is left is a name, a
# date and an Unmute.
class Newsletter::Sender::Row
  include ActionView::Helpers::DateHelper

  delegate :to_param, to: :sender

  def initialize(sender)
    @sender = sender
  end

  # The sender's own name, falling back to the address. A From header need not
  # carry a display name, and the address is the only other thing this app
  # knows about them — the same fallback Blog#name makes to its feed address.
  def name
    sender.name.presence || sender.sender_email
  end

  # How long it has been muted, in the slot a blog's poll state occupies. The
  # distance rather than the clock time, for the reason Blog::Row prints it
  # that way: what the reader needs is how long, not the hour they decided.
  def state
    I18n.t("newsletter_senders.state.silenced", duration: time_ago_in_words(sender.silenced_at))
  end

  def to_partial_path
    "newsletter_senders/row"
  end

  private

  attr_reader :sender
end
