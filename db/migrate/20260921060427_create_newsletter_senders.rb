class CreateNewsletterSenders < ActiveRecord::Migration[8.1]
  # The roster row a newsletter sender has never had. A blog is a row the
  # reader added deliberately; a sender is an address that turned up on some
  # mail, so until there is a decision to record about one there is nothing
  # to store. A row here is that decision.
  #
  # Keyed on the address rather than joined to newsletters, so muting works
  # for mail that has not arrived yet and for a sender whose old issues were
  # never kept. newsletters.sender_email stays the only link.
  def change
    create_table :newsletter_senders do |t|
      # NOCASE because a sender does not write from one casing, and a silence
      # that a changed From header walks past is not one. It applies to the
      # unique index below as well, so two rows differing only in case cannot
      # both exist, and to the comparison in Newsletter::NOT_FROM_A_SILENCED_SENDER,
      # where SQLite takes the collation from the column rather than the literal.
      t.string :sender_email, null: false, collation: "NOCASE"

      # What the reader called it, taken off the mail at the moment they
      # muted. Defaults to "" because a sender's display name is optional in
      # the mail and the roster falls back to the address.
      t.string :name, null: false, default: ""

      # Nullable on purpose: unmuting clears it, so the column is the whole of
      # the state, per .claude/rules/database.md's timestamp-backed boolean.
      t.datetime :silenced_at

      t.timestamps
    end

    # One row per address. The lookup that mutes reads this, and the unique
    # index is what actually holds when two mutes of the same sender race.
    add_index :newsletter_senders, :sender_email, unique: true

    # The roster lists what is muted, and the edition window asks whether
    # anything is. Partial, so it holds only the rows either reader wants.
    add_index :newsletter_senders, :silenced_at, where: "silenced_at IS NOT NULL"
  end
end
