# Read state is retired: triage is the edition's job now, so nothing writes
# this column and nothing reads it. Its index goes with it.
#
# Reversible in shape but not in content — rolling back gives every newsletter
# back as unread, because the timestamps are gone. Nothing depends on them, so
# what is lost is the record of which mail this reader had opened. The deploy
# doc says to take a backup first.
class RemoveReadAtFromNewsletters < ActiveRecord::Migration[8.1]
  def change
    remove_index :newsletters, :read_at
    remove_column :newsletters, :read_at, :datetime
  end
end
