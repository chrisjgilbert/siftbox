class CreateBlogPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :blog_posts do |t|
      t.references :blog, null: false, foreign_key: { on_delete: :cascade }

      # What the feed called this post. Kept as the publisher wrote it, which
      # is why guid defaults to "" rather than being null: an absent guid and
      # an empty one are the same fact — the feed did not name the post — and
      # a nullable column would let the partial index below disagree about it.
      t.string :guid, null: false, default: ""
      t.string :url, null: false, default: ""

      # The reading columns, mirroring newsletters deliberately. The pipeline
      # that scrubs markup, extracts prose and picks a lead image already runs
      # on a body_html and knows nothing about mail, so a post that carries
      # the same column names reads through the same code.
      t.string :title, null: false, default: ""
      t.text :body_html, null: false, default: ""
      t.string :snippet, null: false, default: ""
      t.string :lead_image_url, null: false, default: ""

      # Two clocks, and they are not the same one. published_at is the
      # publisher's claim and is what the archive displays; received_at is
      # when this app first saw the post and is what an edition window runs
      # on, so the edition axis stays a single consistent clock across
      # newsletters and posts alike. A feed's back catalogue is dated years
      # before the day it is first polled.
      t.datetime :published_at
      t.datetime :received_at, null: false

      t.timestamps
    end

    # The same partial-unique shape newsletters already uses for message_id.
    # Scoped to the blog because a guid is only unique within the feed that
    # issued it, and partial because "" means the feed named nothing — and
    # every unnamed post across a blog would otherwise collide with the first.
    add_index :blog_posts, [ :blog_id, :guid ], unique: true,
      where: "guid <> ''", name: "index_blog_posts_on_present_guid"

    # What an edition window filters and the archive sorts on.
    add_index :blog_posts, :received_at
  end
end
