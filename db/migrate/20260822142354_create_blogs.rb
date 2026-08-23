class CreateBlogs < ActiveRecord::Migration[8.1]
  def change
    create_table :blogs do |t|
      # What the reader calls it and where the writing lives, both read off
      # the feed at the first poll rather than typed.
      t.string :title, null: false, default: ""
      t.string :site_url, null: false, default: ""

      # The only thing a blog cannot be without, and the one the reader
      # supplies. Named explicitly because Rails' generated name would not say
      # the index is unique, and docs/briefing-followups.md already records
      # that an index whose name lies costs somebody an afternoon.
      t.string :feed_url, null: false

      # Polling state. The etag and the last-modified header travel back to
      # the blog on the next poll so an unchanged feed answers 304 and costs
      # the publisher nothing.
      #
      # last_modified_header is deliberately not an _at, against the
      # convention in .claude/rules/database.md: it holds the header as the
      # server wrote it, because servers compare it as text. Parsing it to a
      # datetime and re-emitting it is how you get a 200 every time.
      t.datetime :polled_at
      t.string :etag, null: false, default: ""
      t.string :last_modified_header, null: false, default: ""

      # Set when fetching starts failing and cleared when it works again — so
      # the Sources page can say "not fetching since Tuesday" rather than
      # leaving a blog that has quietly stopped publishing to look like a blog
      # that has quietly stopped existing.
      t.datetime :failing_since

      t.timestamps
    end

    add_index :blogs, :feed_url, unique: true, name: "index_blogs_on_unique_feed_url"
  end
end
