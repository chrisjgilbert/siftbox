class CreateEditionStories < ActiveRecord::Migration[8.1]
  # The unit of an edition is the story, not the newsletter: five newsletters
  # covering one event are one row here with five citations, and one newsletter
  # covering five topics contributes to five rows.
  def change
    create_table :edition_stories do |t|
      t.references :edition,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: false
      t.integer :position, null: false

      # lead, briefly or reading_list. Stored as the word rather than an
      # integer enum so the raw table can be read during prompt iteration,
      # which is where most of the looking at this table will happen.
      t.string :section, null: false

      # Optional: a Briefly line is often a single sentence with nothing to put
      # above it, and an invented headline would be the model writing words the
      # sources did not.
      t.string :headline, null: false, default: ""
      t.text :body, null: false, default: ""

      t.timestamps
    end

    # Position runs across the whole edition rather than restarting per
    # section, so this doubles as the ordering index and as the guard against
    # two stories claiming one slot — which would order differently between
    # page loads. The references index on edition_id alone would be a prefix of
    # this one, so it is turned off above rather than stored twice.
    add_index :edition_stories, [ :edition_id, :position ], unique: true
  end
end
