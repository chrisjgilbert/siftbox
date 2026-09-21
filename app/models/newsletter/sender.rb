# An address the reader has made a decision about: a roster row for one of
# the two kinds of source, alongside Blog.
#
# A blog is a row the reader added deliberately and the app then polls. A
# sender is an address that turned up on some mail, so there is nothing to
# store about one until there is a decision to record — which is why a row
# here is made at the moment of muting rather than at ingest. Mail keeps
# arriving from a muted sender and keeps its place in the originals archive;
# what a silence stops is the sender reaching an edition.
#
# Matched to mail on the address rather than through a foreign key, so muting
# covers issues that have not arrived yet and issues whose rows were never
# kept. See Newsletter::NOT_FROM_A_SILENCED_SENDER for the comparison, and the
# migration for why the column is NOCASE.
class Newsletter::Sender < ApplicationRecord
  validates :sender_email, presence: true

  def self.silenced
    where.not(silenced_at: nil)
  end

  # The reader pressing mute on an issue they are reading. Idempotent on the
  # address, because the button is reachable from every issue a sender has
  # ever sent and pressing it twice is not a second decision.
  #
  # create_or_find_by rather than find_or_create_by: the latter reads and then
  # writes, so two mutes of the same sender at once both find nothing and the
  # second insert fails on the unique index. This one writes first and falls
  # back to the read, which is the order that survives the race.
  #
  # Returns nothing for mail carrying no address — Mail parses "From:
  # newsletter" as a one-address list with no address in it, and a roster row
  # keyed on "" would mute every such sender at once.
  def self.muting(newsletter)
    return if newsletter.sender_email.blank?

    sender = create_or_find_by(sender_email: newsletter.sender_email) do |fresh|
      fresh.name = newsletter.sender_name
    end
    sender.silence

    sender
  end

  def silenced?
    silenced_at.present?
  end

  # The first muting stands. Pressing a button whose state is not visible is
  # not a second decision, and the roster prints the date the reader decided.
  def silence
    return if silenced?

    update!(silenced_at: Time.current)
  end

  def unsilence
    return unless silenced?

    update!(silenced_at: nil)
  end
end
