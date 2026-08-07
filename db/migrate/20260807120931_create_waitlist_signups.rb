class CreateWaitlistSignups < ActiveRecord::Migration[8.0]
  # The unique index is what makes a duplicate signup safe to treat as a
  # success: the insert raises, WaitlistSignup#join rescues, and nobody
  # learns whose address is already on the list.
  def change
    create_table :waitlist_signups do |t|
      t.string :email, null: false

      t.timestamps
    end

    add_index :waitlist_signups, :email, unique: true
  end
end
