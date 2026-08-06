# Database and migrations

## Migrations

- Generate migrations with `bin/rails generate migration`, never by hand.
- Foreign key constraints with an explicit `on_delete`.
- `null: false` and database-level defaults where they apply. Optional string and text columns
  default to `""`.
- Plain SQL in migrations, not model classes — the model will change later and the migration
  won't.
- Once merged, don't edit a migration. Add another one.
- `db/schema.rb` is committed.
- `db/seeds.rb` holds data every environment needs. Development sample data goes in a separate
  task.

## Columns

- `text` over `string` when the length varies a lot.
- `_at` for datetimes, `_on` for dates, `_time` for a time of day with no date.
- Back a boolean concept with a timestamp, so you know when it happened:

```ruby
# schema
t.datetime :archived_at

# model
def archived?
  archived_at.present?
end
```

- Add an index when you add a column you'll query or sort on.

## Queries

- Never `Post.all` without pagination.
- No `.count` inside a loop. Use `counter_cache` or a single grouped query.
- Wrap multi-record writes in a transaction, and use the bang methods (`save!`, `update!`)
  inside it so a failure actually rolls back.
- Preload associations a view will touch. An N+1 in a partial is the usual cause.
- `Time.current`, `Date.current`, `Time.zone.parse` — not `Time.now`, `Date.today`,
  `Time.parse`.

```ruby
# Before — N+1 plus a count per row
orders.each { |order| puts order.line_items.count }

# After
orders.includes(:line_items).each { |order| puts order.line_items.size }
```
