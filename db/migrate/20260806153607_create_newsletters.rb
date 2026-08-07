class CreateNewsletters < ActiveRecord::Migration[8.0]
  def change
    create_table :newsletters do |t|
      t.string :message_id, null: false, default: ""
      t.string :sender_name, null: false, default: ""
      t.string :sender_email, null: false, default: ""
      t.string :subject, null: false, default: ""
      t.string :snippet, null: false, default: ""
      t.text :body_html, null: false, default: ""
      t.datetime :received_at, null: false
      t.datetime :read_at

      t.timestamps
    end

    add_index :newsletters, :sender_email
    add_index :newsletters, :received_at
    add_index :newsletters, :read_at

    # Optional strings default to "" rather than NULL, so a plain unique index
    # would collide on every message arriving without a Message-ID header.
    add_index :newsletters,
      :message_id,
      unique: true,
      where: "message_id <> ''",
      name: "index_newsletters_on_present_message_id"
  end
end
