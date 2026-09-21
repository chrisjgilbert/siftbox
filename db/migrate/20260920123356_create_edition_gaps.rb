class CreateEditionGaps < ActiveRecord::Migration[8.1]
  # A morning that produced no edition, and why.
  #
  # The watermark was read off published editions alone, which cannot tell
  # "the job never ran" from "the job ran and found nothing" from "the job ran
  # and failed". Only the first of those should make the next window bigger;
  # the other two have already been accounted for. Without the distinction a
  # quiet spell freezes the watermark for its whole length, and a run of
  # failures aims a multi-day window at a token ceiling it cannot clear.
  #
  # So every morning is written down: an edition when there was one, a gap
  # when there was not. Both carry the window they covered, and the watermark
  # is the newer of the two.
  def change
    # covered_on mirrors editions.published_on, uniquely indexed for the same
    # reason: one morning has one outcome, and the archive files the two
    # together by the day each covered.
    create_table :edition_gaps do |t|
      t.date :covered_on, null: false
      t.string :reason, null: false
      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false

      # Whatever the failure said for itself. text rather than string because
      # the length varies from a sentence to a provider's whole error body.
      t.text :detail, null: false, default: ""

      t.timestamps
    end

    add_index :edition_gaps, :covered_on, unique: true

    # The other half of the watermark lookup, and the same shape as
    # index_editions_on_window_ended_at: composition asks for the maximum of
    # this column before it asks for anything else.
    add_index :edition_gaps, :window_ended_at
  end
end
