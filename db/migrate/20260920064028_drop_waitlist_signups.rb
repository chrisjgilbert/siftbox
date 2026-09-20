class DropWaitlistSignups < ActiveRecord::Migration[8.0]
  # The whole definition, index included, sits inside the block so a rollback
  # builds the table back. It reverses in shape and not in content: the
  # addresses are gone, and nothing in this repository has a copy. Back the
  # volume up before the deploy — docs/deploying.md says so beside the
  # read-state migration, which reverses the same way.
  def change
    drop_table :waitlist_signups do |t|
      t.string :email, null: false

      t.timestamps

      t.index :email, unique: true
    end
  end
end
