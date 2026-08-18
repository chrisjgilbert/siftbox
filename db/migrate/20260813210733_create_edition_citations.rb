class CreateEditionCitations < ActiveRecord::Migration[8.1]
  # What a story was written from. Kept as a table rather than a column of ids
  # on edition_stories because it is also the completeness check's index: every
  # newsletter in the window has to appear here at least once, and that is a
  # query, not a scan of serialised arrays.
  #
  # It is the seam RSS items plug into later as a second source type. Not
  # polymorphic now — there is no second type to be polymorphic over — but a
  # real table is what leaves the seam open.
  def change
    create_table :edition_citations do |t|
      t.references :edition_story,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: false

      # Indexed by the reference: the completeness check asks the question from
      # this end — was this newsletter cited anywhere.
      t.references :newsletter, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    # A story citing one newsletter twice would print the same source twice
    # under the same paragraph. The model emits the ids, so a repeat is one
    # duplicated array element away; the constraint is what makes the writer
    # able to insert them without deduplicating first.
    add_index :edition_citations, [ :edition_story_id, :newsletter_id ], unique: true
  end
end
