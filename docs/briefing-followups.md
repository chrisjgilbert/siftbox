# Editions — parked follow-ups

Findings from the review passes that were deliberately not fixed at the time
they were found, with the milestone that should pick each one up. Fixed
findings are not listed; they are in the diff.

## Milestone 2 — what an API key has still to prove

The editor has never made a request. Every spec runs against `FakeAnthropic`,
and the corpus in `lib/edition_corpus.rb` is answered by a fake that was handed
the expected answer, so what is green here is the plumbing and nothing else.
What that leaves unproven, in the order it will be found out:

- **That claude-opus-5 accepts the request as built.** The `output_config`
  shape, `system_`, the effort level, the JSON schema and the streaming call
  have been checked against the SDK's own interface and the API reference,
  never against the API. A 400 on the first real call is a live possibility,
  and `Edition::Draft::Rejected` is what it will arrive as.

- **That the schema is honoured.** Nothing has confirmed the model returns
  `section` values from the enum, cites integers that are newsletter ids, or
  keeps to `additionalProperties: false`. `Edition::Editor` catches an id that
  was not in the window; it cannot catch a section word that is not a section,
  which surfaces as a validation failure on the story.

- **Everything Milestone 0 is for.** Clustering, attribution, selection and
  classification are judged by a person reading `edition:backtest` output.
  The corpus states what a good answer looks like — one story off three
  senders, the tutorial on the reading list, the teaser's paywall named — but
  the only evidence so far is that composition puts such an answer in the
  right places, not that a model produces one.

- **Whether regeneration converges.** The completeness check has never failed
  against a real answer, so nobody knows if the first attempt usually passes.
  A retry re-sends the identical prompt without saying which newsletter went
  missing; if three blind rolls turn out not to be enough, the fix is a
  correction in `Edition::Prompt` and a `VERSION` bump.

- **The cost and the ceiling.** ~$0.45 a day is arithmetic over an assumed
  60k input tokens, not a measurement, and `MAX_TOKENS = 32_000` has never
  been tested against thinking plus a full edition — `Truncated` may be
  routine on a catch-up window or may never fire. The backtest prints the real
  figures per run, which is where the answer comes from. `EFFORT = "high"` has
  never been compared with `medium` or `xhigh`; a sweep belongs in the same
  session.

- **Refusals and streaming.** `stop_details.category` has never been seen on a
  real response, and `accumulated_message` was verified by reflection against
  the installed gem rather than against a live stream.

What the corpus itself does not cover, so a backtest over real mail is not
optional:

- **No newsletter in it carries more than one item.** "One newsletter may
  carry five items" is exactly the case the corpus cannot check, and
  link-roundup senders (AINews) are the ones the PRD already suspects. Real
  mail is where that gets tested.
- **Nothing in it is image-only, oversized, or non-English**, so the
  per-source cap, the empty-prose path and the PRD's two-pass chunking for a
  window that overflows are all untouched by it.

Two smaller things this milestone found and left alone:

- **`Newsletter::Prose` misses "Read in the app".** `CHROME_LABELS` matches
  "read in app" and "read on the app" but not the article in between, so that
  footer line reaches the editor as content. It is one junk line and the
  anchored-label rule is deliberately conservative, but the pattern is worth a
  word when someone next touches that list.
- **`edition:backtest` cannot rehearse a day that already has an edition.**
  The rehearsal is validated like the real thing, and `published_on` is
  unique. Harmless until the schedule ships; after that, re-reading a window
  wants the regenerate task the PRD sketches, which has to decide what happens
  to the edition already sitting on that date.

## For Milestone 3 — publishing and the window

- **The edition window is two-clause, and nothing enforces that yet.**
  Three separate review agents flagged this independently, which is a good
  sign it is easy to get wrong. The window is *not*
  `received_at BETWEEN a AND b` — it is that OR `released_at BETWEEN a AND b`,
  because a newsletter released out of the confirmation pen has a
  `received_at` behind the watermark by the time it is released. Getting it
  wrong silently drops released mail from every edition. `Newsletter.released`
  exists for the second clause. Consequence worth a comment wherever the
  window ends up: `window_started_at`/`window_ended_at` describe the
  `received_at` axis only, so a released newsletter can legitimately sit
  outside the recorded window of the edition citing it.

- **Nothing allocates `Edition#number`.** It is required and uniquely
  indexed, but no default, callback or class method assigns it — only the
  factory's sequence. The composer will need `maximum(:number) + 1`, and a
  retried composition job has to tolerate `ActiveRecord::RecordNotUnique`,
  since the unique index is what turns a race into a failed insert rather
  than two editions numbered 4. Allocation belongs on `Edition`, not on
  whoever happens to create one.

- **`number` and `published_on` can disagree about order.** `newest_first`
  sorts by `published_on`, and nothing ties the masthead number to that
  sequence. `maximum(:number) + 1` inverts them in exactly the case the model
  is built around: an edition composed late for an earlier day takes the
  higher number but sorts below the day that beat it out, so the archive
  reads No. 1, No. 3, No. 2. Decide whether the number follows the date or
  the composition order — and if the date, allocation cannot simply be a max
  plus one.

- **`index_editions_on_window_ended_at` is unpaid-for until this milestone.**
  It exists for the watermark query (`maximum(:window_ended_at)`), which does
  not ship until here.

## For Milestone 4 — the edition pages

- **N+1 on citations.** `Edition#lead_stories`, `#briefly` and `#reading_list`
  correctly load the stories once and partition in Ruby, but each story's
  `newsletters` fires its own query on first touch. An edition of ~15 stories
  costs 15 extra queries. The read site needs
  `Edition.newest_first.includes(stories: :newsletters).first`, which keeps
  the `in_position_order` association scope and flattens it to four queries
  regardless of story count.

- **Citation links pull full `body_html`.** `has_many :newsletters, through:
  :citations` selects `newsletters.*`, and bodies run to hundreds of
  kilobytes — 45 citations is tens of megabytes read to render source names.
  The house pattern is a column list (`Newsletter::FEED_COLUMNS`,
  `NEIGHBOUR_COLUMNS`); this wants the same, scoped on the association, once
  the view has settled which columns it actually needs.

- **The section readers are layout, and they live on the record.**
  `lead_stories` / `briefly` / `reading_list` / `reading_list?` decide what
  the page draws, which `.claude/rules/views.md` puts in a presenter. This
  milestone needs an edition presenter anyway for the masthead, so it should
  either wrap these or take them over rather than duplicate them.

- **Section names have no view-facing accessor.** The template cannot say
  `Edition::Story::LEAD` — a view never references a model class. The
  codebase already solved this once: `Feed#unread_filter` exists purely so a
  template need not name `Feed::UNREAD`, and cites the rule in its comment.
  The edition presenter needs the equivalent.

## For Milestone 2 and 5 — the confirmation pen

- **The backfill must go through `#hold`.** The state machine is held
  together by two validations rather than a database CHECK constraint, so
  the bulk-write path the backtests want (`update_all`, `insert_all`) would
  walk straight past it. The PRD's backfill task has to call the verb.

- **Undecided in the PRD:** whether a newsletter already cited in a published
  edition may be held retroactively by the backfill. Nothing currently
  prevents it, and the citation would then point at mail the archive hides.
  Worth deciding before the backfill is written.

## Undecided design

- **Deleting a newsletter guts the editions that cite it.**
  `edition_citations.newsletter_id` cascades on delete, so removing a
  newsletter silently strips it from the stories of published — supposedly
  immutable — editions, leaving claims with no source behind them. There is
  no delete path in production today, and the development sample-data task
  now clears editions first so it cannot leave that state behind, so nothing
  is broken right now. The open question is what *should* happen: `restrict`
  says a cited newsletter is pinned by the edition citing it, which fits
  "every claim traces to a source I can open", but it would mean anything
  clearing newsletters has to clear editions first. Worth deciding before
  there is any way to delete a newsletter from the app.

## Smaller, no particular milestone

- **`Newsletter.content` scans when unbounded.** Verified with
  `EXPLAIN QUERY PLAN`: as the archive actually calls it, the `received_at`
  index carries the query and the hold predicates are evaluated over a narrow
  window, so it is fine today. Unbounded — `Newsletter.content` with no date
  filter — it is a full scan, because the partial index on `held_at` covers
  `IS NOT NULL` and cannot serve the `IS NULL` branch. Anything that calls it
  without a date bound needs a second look.

- **The new partial indexes take Rails' auto-generated names.**
  `index_newsletters_on_held_at` does not say it is partial, so a later plain
  `add_index :newsletters, :held_at` collides on a name that reads as though
  it should be free. The existing partial index in
  `20260806153607_create_newsletters.rb` names itself explicitly
  (`index_newsletters_on_present_message_id`). Not fixed because the
  migrations are applied and churning them to rename an index risks more than
  it saves — but worth knowing the name lies.

- **`spec/models/edition/citation_spec.rb` duplicates the `table_name` pin**
  already made, with a fuller explanation, in
  `spec/models/edition/story_spec.rb`. The second copy pins nothing new, so a
  change to Rails' derivation rule breaks two specs and is diagnosed twice.

- **Rationale is duplicated between migrations and models** — the section
  column's storage-as-a-word, the citation table's RSS seam, and the reason
  `published_at` is unindexed each appear in both places, near-verbatim.
  Migrations cannot be edited once merged, so the copies are guaranteed to
  drift. Storage rationale belongs in the migration, behaviour rationale in
  the model.

## Considered and rejected

- **Extracting `Newsletter::Confirmation`.** Two review agents disagreed on
  this one. Against extraction, decisively: of `newsletter.rb`'s 194 lines,
  63 are comments and 33 blank, so the actual code is 98 lines — at the
  guidance in `.claude/rules/ruby.md`, not past it. The two validations and
  the four query methods have to stay on the ActiveRecord class regardless,
  so a PORO could only take the three verbs and the predicates, splitting one
  invariant across two files: a reader asking "can this be dismissed?" would
  have to open both. Revisit if Milestone 5 adds materially to it. If line
  count alone ever forces the issue, the cleaner seam is the pre-existing
  neighbour chain (`NEIGHBOUR_COLUMNS`, `.neighbour`, `#newer`, `#older`),
  which is self-contained and shares no state with the rest.

- **Replacing `dismissed_at`/`released_at` with `resolved_at` plus a
  `resolution` string.** It would make the illegal both-set state
  unrepresentable and delete one validation. Rejected because
  `.claude/rules/database.md` asks for a timestamp behind each boolean
  concept, the saving is one validation and one predicate, and the two
  validations already close the hole.
