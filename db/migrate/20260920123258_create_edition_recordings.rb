class CreateEditionRecordings < ActiveRecord::Migration[8.1]
  def change
    create_table :edition_recordings do |t|
      # Unique rather than a plain reference: an edition has one recording,
      # and the index is what says so rather than a validation that two
      # simultaneous taps of "Play edition" would both read as clear. The
      # cascade matches every other edition child — a destroyed edition takes
      # its recording with it, and the attached blob goes with the row through
      # Active Storage's own dependent purge.
      t.references :edition, null: false, index: { unique: true },
        foreign_key: { on_delete: :cascade }

      # Which voice said it, in the shape editions.editor_model already
      # records which model wrote it: vendor, model and voice as one string,
      # so a recording that sounds wrong months later can be told from one
      # made by a voice since changed. Defaulted to "" rather than nullable
      # for the reason the editor column is — a recording that names no voice
      # and one that names an empty voice are the same fact.
      t.string :voice, null: false, default: ""

      # Three clocks rather than a status column, per the house rule on
      # backing a boolean concept with a timestamp. requested_at is when the
      # reader asked, so a recording stuck pending can be told from one asked
      # for a second ago; the other two are nullable because a recording that
      # has neither completed nor failed is the ordinary state for the few
      # seconds the job is running.
      #
      # Both nullable and neither indexed: a recording is only ever reached
      # through its edition, and the unique index above serves that read.
      t.datetime :requested_at, null: false
      t.datetime :completed_at
      t.datetime :failed_at

      t.timestamps
    end
  end
end
