class AddConfirmationHoldToNewsletters < ActiveRecord::Migration[8.1]
  # The subscription-confirmation lifecycle, as timestamps rather than
  # booleans, so the pen can say "4 minutes ago" — which is the whole point of
  # the page, since confirm links expire within a day or two.
  #
  # Held at ingest, then resolved one of two ways: dismissed (confirmed, or
  # just cleared) or released (the heuristic misfired and this is content).
  # Both stay set afterwards, so a released newsletter still remembers it was
  # once held and the phrase set can be judged against real misfires.
  def change
    add_column :newsletters, :held_at, :datetime
    add_column :newsletters, :dismissed_at, :datetime
    add_column :newsletters, :released_at, :datetime

    # Partial, because SQLite stores NULLs in an index and a plain index here
    # would be one entry per newsletter ever received to find the handful the
    # pen shows. Nothing indexes dismissed_at: it is only ever read within the
    # held set, which is small enough to filter and sort in place.
    add_index :newsletters, :held_at, where: "held_at IS NOT NULL"

    # A release makes an old newsletter current again — it joins the next
    # edition even though its received_at is behind the watermark, so the
    # window query is an OR across two columns and needs both sides indexed to
    # avoid a full scan on the received_at side's alternative.
    add_index :newsletters, :released_at, where: "released_at IS NOT NULL"
  end
end
