# The second source type the citations table was built expecting. A story is
# written from mail, from blog posts, or from both, and a citation names
# exactly one of them.
#
# Two nullable columns and a check constraint rather than a polymorphic pair,
# for the reason docs/blogs-rss.md sets out at length: a type string and an
# untyped integer cannot be constrained by the database, so nothing stops a
# citation pointing at a row that is not there. Two real foreign keys can be,
# and are.
class CiteBlogPostsInEditions < ActiveRecord::Migration[8.1]
  def change
    add_reference :edition_citations, :blog_post, foreign_key: { on_delete: :cascade }

    # newsletter_id stops being mandatory now that it has an alternative. The
    # check constraint below is what keeps it from becoming optional in the
    # sense of absent — a row still has to name one of the two.
    change_column_null :edition_citations, :newsletter_id, true

    # Exactly one, expressed as a count rather than as a pair of implications:
    # one clause to read, and it stays one clause if a third source type ever
    # arrives.
    add_check_constraint :edition_citations,
      "(newsletter_id IS NOT NULL) + (blog_post_id IS NOT NULL) = 1",
      name: "edition_citations_name_one_source"

    # The same guarantee the newsletter side already has: a story cites a post
    # once. Partial, because every mail citation leaves blog_post_id NULL and
    # SQLite counts NULLs as distinct — the index would hold either way, but
    # only the partial one stays the size of the posts actually cited.
    add_index :edition_citations, [ :edition_story_id, :blog_post_id ],
      unique: true, where: "blog_post_id IS NOT NULL",
      name: "index_edition_citations_on_story_and_post"
  end
end
