class AddDesignedLayoutToNewsletters < ActiveRecord::Migration[8.1]
  # Not null and defaulting to false, so every newsletter already stored reads
  # as prose — which is what the reader does with them today. The backfill
  # task reads the archive's real shapes afterwards.
  def change
    add_column :newsletters, :designed_layout, :boolean, default: false, null: false
  end
end
