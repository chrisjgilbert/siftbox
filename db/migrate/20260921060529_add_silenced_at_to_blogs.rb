class AddSilencedAtToBlogs < ActiveRecord::Migration[8.1]
  # The blog's half of the roster's one decision. A blog is already the row
  # the reader added, so muting is a column on it rather than a second table
  # standing beside it — which is the whole difference from a newsletter
  # sender, who had no row at all until Newsletter::Sender.
  #
  # Nullable on purpose: unmuting clears it, so the column is the whole of the
  # state, per .claude/rules/database.md's timestamp-backed boolean.
  #
  # Muting is not removing. BlogsController#destroy takes the posts and the
  # citations naming them; this leaves both where they are and only stops the
  # blog reaching an edition.
  def change
    add_column :blogs, :silenced_at, :datetime

    # Both readers want only the muted rows: the roster lists them, and the
    # edition window asks whether a post's blog is one. Partial for the same
    # reason index_newsletter_senders_on_silenced_at is.
    add_index :blogs, :silenced_at, where: "silenced_at IS NOT NULL"
  end
end
