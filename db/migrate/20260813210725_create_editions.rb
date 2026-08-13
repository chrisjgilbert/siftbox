class CreateEditions < ActiveRecord::Migration[8.1]
  # An edition is immutable once published: the prompt changes, the next
  # edition changes, and this row stays as it was. That is why what the model
  # said is stored beside what it produced — a bad edition can be read back
  # and recomposed without re-fetching a single newsletter.
  def change
    create_table :editions do |t|
      t.integer :number, null: false
      t.date :published_on, null: false
      t.datetime :published_at, null: false
      t.datetime :window_started_at, null: false
      t.datetime :window_ended_at, null: false

      # Not `model`: ActiveRecord and ActiveModel both answer to model_name,
      # model_name.param_key and friends, and a column called `model` puts an
      # attribute reader next door to that machinery for anything doing
      # `edition.model` — including form builders and url_for.
      t.string :editor_model, null: false, default: ""
      t.string :prompt_version, null: false, default: ""
      t.text :raw_response, null: false, default: ""

      # Lifted out of raw_response, where the provider already reports them,
      # so a month of cost is a SUM rather than a JSON parse over every row.
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0

      t.timestamps
    end

    # One edition a day, and the masthead numbers its own sequence from No. 1.
    # Both unique, because a retried composition job that half-succeeded is the
    # likely second writer, and two editions dated the same day would leave the
    # archive with no way to say which one the reader is looking at.
    add_index :editions, :number, unique: true
    add_index :editions, :published_on, unique: true

    # The watermark lookup: the next window starts where the last one ended, so
    # composition asks for the maximum of this column before it asks for
    # anything else. published_at gets no index — an edition composed late is
    # still that day's edition, so ordering is always by date or number, never
    # by the wall clock the job happened to finish on.
    add_index :editions, :window_ended_at
  end
end
