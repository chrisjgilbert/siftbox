# Plan: blogs via RSS

The decisions behind this are in `docs/blogs-rss.md`, taken against the
built code and a measurement of ten real feeds. Settled going in:

- **Storage is a sibling table.** `blogs` and `blog_posts` beside
  `newsletters`, with typed foreign keys throughout and no polymorphic
  pointer anywhere — per GitLab's database guidelines, and because it
  migrates nothing that already exists.
- **Aggregator feeds are out of scope.** A feed whose items carry no body
  is a list of links, not a source.
- **Parsing is `rss` (ruby/rss), wrapped in one adapter.** Verified against
  the eight in-scope feeds: all eight parse in strict mode, dates come back
  as `Time`, and its REXML backing refuses entity bombs and does not
  resolve external entities.
- **Names.** `Blog`, `Blog::Post`, `Blog::Feed`, `Blog::Feed::Item`,
  `Blog::Poll`, `Blog::PollJob` — because `Feed`, `Newsletter::Source` and
  `Edition::Story::Presenter::Source` are all taken.

Four milestones, each a branch and a deploy on its own. There is no
refactor milestone: an earlier draft of this plan opened with one, moving
the whole archive under a shared `items` table before a single post
existed. Option B deletes it.

## How each one is worked

Not restated per milestone, because it is the same every time:

- **The test comes first.** `.claude/rules/testing.md` — red, green,
  refactor, no implementation ahead of a failing test. Setup inside the
  example; no `let`, no `before`.
- **Migrations are generated**, never hand-written, and never edited once
  merged. `db/schema.rb` is committed with them.
- **`bin/ci` is the gate**: rspec, rubocop, brakeman, bundle-audit.
- **Style-only changes go in their own commit.**
- **Comments carry the reasoning, in this codebase's register.** Several of
  the classes being generalised have their rationale written above them; it
  moves with them, updated where the move makes it untrue.

## Coordinating with the silencing branch

`claude/mute-newsletters-reports-kh0rro` (`docs/silencing.md`) is scoping
silencing at the same time, and the two branches share a roster. Agreed
here, with one open difference recorded in Decision 1b of
`docs/blogs-rss.md`:

- **One `sources` table serves both kinds.** Conceded — this branch's
  earlier objection assumed the two cases would arrive months apart, and
  they are concurrent.
- **Settled: typed references, not a shared identifier string.** `sources`
  carries `sender_email` for mail and a `blog_id` foreign key for feeds,
  with a check constraint that exactly one is set, another that
  `sender_email` is non-empty, and no `kind` column. `Blog` stays whole.
- **Settled: `NOT EXISTS`, not a guarded subquery**, on both branches, for
  structural immunity to the NULL trap rather than a guard every future
  scope has to remember.
- **Sequenced so their branch is not blocked.** `sources` ships mail-only
  there; the `blog_id` column, its check constraint and its index arrive
  additively here in Milestone 1, against a table that already exists.
- **`Newsletter::Source` → `Newsletter::Markup`** lands there, in its own
  commit, before either branch references a top-level `Source`. Nothing
  here adds new references to it in the meantime.
- **`Edition::Window` is edited by both.** They take the rebase if they
  land second. Milestone 2 below merges two relations; the silence test
  applies to **both** of them, as a correlated `NOT EXISTS`.
- **The Subscriptions page.** That branch owns the Sources section and the
  mute state; this one contributes the add-a-feed form and the aggregator
  refusal in Milestone 3, rendering into their section rather than beside
  it.
- **Silencing is not staged here.** It is that branch's feature on that
  branch's timeline. It appears under Parked below only so this plan does
  not look as though it forgot.

## Milestone 0 — finish the measurement

The spike in `docs/blogs-rss.md` was run by hand, once, against a plausible
feed list. Make it a task and point it at the real one.

**Build**

- `lib/tasks/feeds.rake` — `feeds:measure`, development only, taking a list
  of feed URLs. Fetches, parses, runs each item through
  `Newsletter::Prose`, and prints per feed: item count, items in the last
  1/7/30 days, prose length median and maximum, how many hit
  `MAXIMUM_CHARACTERS`, and how many fall under a candidate prose floor.
- Store nothing. No migration, no model, no route.

**Done when** it has run against the reader's own feeds on several
different days, and two numbers have come out of it: the prose floor, and
whether any intended subscription behaves like an aggregator.

**Why it is first** — the ten feeds measured are not the reader's, and one
snapshot already reversed a conclusion in the investigation. It is cheap,
and it is the last chance to find out the scope is wrong before a table
exists.

## Milestone 1 — fetch and store

Blogs arrive. Posts appear in the archive. Editions do not see them yet.

### The schema

Two migrations, both additive, neither touching `newsletters`:

1. **`blogs`** — `title`, `feed_url` (unique), `site_url`, `polled_at`,
   `etag`, `last_modified_header`, `failing_since`. Optional strings
   default to `""`. `last_modified_header` is deliberately not `_at`: it
   stores the header as text because servers compare it as text, and a
   re-emitted timestamp is how you get a 200 on every poll.
2. **`blog_posts`** — `blog_id` (FK, `on_delete: :cascade`), `guid`, `url`,
   `title`, `body_html`, `snippet`, `lead_image_url`, `published_at`,
   `received_at`. Partial unique index on `(blog_id, guid) where guid <> ''`,
   the shape `newsletters` already uses for `message_id`. Index
   `received_at`.

The columns mirror `newsletters` on purpose — the reading pipeline is
already shared, and this is what lets it stay shared.

**Plus a third, if the silencing branch has landed:** `sources` gains
`blog_id` (FK, `on_delete: :cascade`), the check constraint tying it to
`sender_email` so exactly one is set, and a partial unique index. Additive
against a table that already exists — that sequencing is what keeps their
branch from being blocked on this one.

It also carries a spec that could not be written on their branch, because
it needs `blog_id` to exist: **a silenced source with no `sender_email`
must not empty the window.** That is the `NOT IN` trap, and the correlated
`NOT EXISTS` is what makes it pass. Flagged on both sides so neither
assumes the other has it.

### The ingest path

- **`Blog::Feed`** and **`Blog::Feed::Item`** — the parsed document and one
  normalised entry. This is the fifteen-line adapter over `rss`: `items` is
  uniform across formats, the four fields under it are not (`title` against
  `title.content`, `guid.content` against `id.content`,
  `content_encoded || description` against
  `content.content || summary.content`, `pubDate` against
  `published.content || updated.content`). Pin the entity limits here with
  a spec rather than inheriting a REXML default a later Ruby could move.
- **`Blog::Poll`** — one visit to a feed, with `#save`, deliberately
  echoing `Newsletter::InboundMessage#save`. The two are the same job: read
  something from outside, store what is new, be idempotent about the rest.
  The parallel is worth being able to see.
- **`Blog::PollJob`** — one blog, off the request path.
- **Dedupe**: `guid`, falling back to the item's link, falling back to a
  digest of title and published date, scoped to the blog. First fetch wins;
  an edited post is not re-stored, because a citation is a promise about
  what was read.
- **The first-poll guard**, per Decision 4. Feeds carry back catalogues —
  the eight in-scope feeds hold 273 items and 520k tokens of prose between
  them, against a 200k context. On a blog's first poll everything is stored
  for the archive, but only items published inside a bounded recency window
  get a `received_at` above the watermark. One clearly-named method with the
  reasoning above it, not an incidental `.limit`.

### The fetch

- **`Newsletter::ImageDownload::Destination` moves up unchanged.** It
  already takes a bare `URI` and answers with an address to dial, checks
  every address a name resolves to, and unmaps IPv4-in-IPv6. Nothing in it
  mentions images. Feed URLs are typed by the reader rather than sent by
  strangers, which does not lower the stakes: a blog can redirect to
  `169.254.169.254`, and this app follows redirects from inside its own
  network.
- **`ImageDownload` splits.** Its generic half — redirect ceiling, byte
  cap, wall-clock deadline, the `FAILURES` list, the streamed body checked
  against both `Content-Length` and the actual bytes — becomes a shared
  fetcher. `ImageDownload` keeps its content-type allowlist and calls it.
- **Feeds get their own byte cap, larger than the image one.** Dan Luu's
  feed measured 11.2MB against `MAX_BYTES` of 5MB, so borrowing the image
  ceiling silently refuses a legitimate blog.
- **Read feed bytes as UTF-8 explicitly**, decided in the fetch rather than
  at the parse. A US-ASCII-tagged string fails every feed in the measured
  set with `ArgumentError: invalid byte sequence` — the same class of
  problem `Newsletter::InboundMessage#utf8` exists to solve on the mail
  path. A feed declares its encoding twice, in the XML declaration and the
  HTTP `charset`, and the two are free to disagree or both be missing.
- **Conditional GET.** Send the stored `etag` and `last_modified_header`
  back; a 304 is the common case and costs nothing.

### Images

`Newsletter::RemoteImages` goes generic and leaves the `Newsletter::`
namespace. It already asks the record for `body_html`, `inline_images`,
`inline_image_path`, `transaction` and `update!` — a rename and a moved
file, not a rewrite. `Blog::Post` answers all five.

**A post needs its own images route, and the existing one must not move.**
`Newsletters::ImagesController` says why in its own comment: the paths it
serves "are baked into `body_html` at ingest". Every stored newsletter body
contains `/newsletters/:id/images/:blob` as literal text. So
`#inline_image_path` stays a method each record answers for itself, posts
get `/blog_posts/:id/images/:blob`, and nothing rewrites a stored body.

`Newsletter::InlineImages` does not move and gains nothing: a post has no
MIME parts and no `cid:` references, so it is the one part of the pipeline
posts have no use for.

### The archive

`Feed` merges two queries. It already loads its whole window into memory to
partition it by day, so this is a merge in Ruby rather than a `UNION`.

**Ordering needs a third key.** Every ordering in this app breaks ties on
`id`, because date headers carry whole seconds and a batch send ties.
That argument does not survive a merge — newsletter 5 and post 5 are not
comparable — so the merged ordering is over `(received_at, type, id)`, and
the comment explaining why the tie-break exists has to say so. Get this
wrong and rows reorder between page loads, which is what the existing
comments are warning about.

`Feed::Row` and the `newsletters/_row` partial take a presenter, so a post
needs a presenter answering the same handful of methods, not a second
partial.

**A post's "view original" leaves the app.** For mail the original is the
sender's HTML in a sandboxed frame, and `Newsletter::Source` embeds inline
images as data URIs because that frame has an opaque origin. A post has no
inline images and its real original is the blog's own URL, always present
in the feed item — so it is an external link. Simpler than the mail case,
and the PRD's parked "canonical web links" idea arriving free on one source
type.

### Keeping posts out of editions, on purpose

`Edition::Window` queries `Newsletter` today, so under Option B posts stay
out of editions by simply not being added yet. No temporary scope, no flag,
nothing to remember to delete — a second thing Option B saves that Option C
would have cost.

### The schedule

`config/recurring.yml` gains a poll task, production only, hourly. Cadence
barely matters against a daily edition — it only decides how stale an item
can be when the window closes — and hourly is polite with conditional GET
doing the work. `spec/config/recurring_spec.rb` gains the matching checks:
the class resolves, and Fugit reads the schedule as a `Fugit::Cron` rather
than a duration or an interval.

**This is a deploy step.** The task does not install itself — the row in
`solid_queue_recurring_tasks` is written when the scheduler boots, so the
schedule exists only after a deploy that carries it. `docs/deploying.md`
§9 documents this for `compose_edition` and gains the same for polling,
including the `SolidQueue::RecurringTask.all` confirmation command.

### Done when

Feeds seeded by hand poll on schedule; posts appear in the archive
interleaved with newsletters in a stable order; opening one goes to the
blog; images are stored locally and served from this app; a second poll of
an unchanged feed stores nothing and ideally fetches nothing. `bin/ci`
green, and `spec/support/query_counter.rb` used on the archive — a merged
feed is where an N+1 would appear.

## Milestone 2 — into editions

**The schema**: one migration. `edition_citations` gains nullable
`blog_post_id` with a foreign key and an explicit `on_delete`, plus a check
constraint that exactly one of the two source columns is set.

**The edition path**, and this is where Option B's permanent cost lands —
roughly eighty lines across six files:

- `Edition::Window` merges two relations, with the same
  `(received_at, type, id)` total order as the archive, and the second
  clause for mail released out of the pen still applying only to mail.
  **If silencing has landed, the silence test applies to both relations** —
  the blog one is the easy one to miss, because it arrives already written.
  It wants a spec that fails when either is left out, and the `NOT IN`
  NULL guard from Decision 1b.
- `Edition::Prompt` quotes posts as `<post id="...">` beside
  `<newsletter id="...">`, and `SCHEMA` gains `post_ids` beside
  `newsletter_ids`. Keeping them separate rather than unifying is
  deliberate: attribution differs by kind, and "the newsletter reports" is
  wrong over a blog. `VERSION` goes to 2.
- `Edition::Editor#faults_in` does its set arithmetic twice, and the
  `Incomplete` message names which kind went uncited.
- `Edition::Citation` gains `belongs_to :blog_post, optional: true` and a
  validation that exactly one target is set — the check constraint is the
  floor, this is so it reads as a validation failure rather than a
  database error.
- `Edition::Story` grows a second `has_many :through`, scoped to citation
  columns the way the first is; `Edition::Story::Presenter#sources` unions
  them in citation order.

**Also in this milestone:**

- **The prose floor** from Milestone 0: an item under it is stored for the
  archive but never enters a window. Legitimate blogs still carry stubs —
  9 of the 273 measured items came in under 400 characters, mostly Martin
  Fowler's linked essay fragments and Simon Willison's release notes. It is
  this app deciding an item is not worth reporting, so it says so rather
  than dropping quietly.
- **The truncation marker**, per Decision 3: a feed carrying a summary only
  gets a line saying so in the prose the editor reads, the way
  `Newsletter::Prose::OMISSION` already names this app's own cut. Without
  it the editor classifies a summary feed as the PRD's *teaser* nature and
  reports a blog as paywalled, which is a falsehood. "Truncated" has no
  reliable detector — Dan Luu ships full articles in `<summary>`, Simon
  Willison's short posts are short by design — so this is a heuristic and
  should read as one.

**Not doing**: relaxing the completeness guarantee, and a per-blog cap. At
3.1 items a day across eight blogs neither is needed, and
`.claude/rules/ruby.md` is explicit about not writing code for
functionality that does not exist yet.

**Done when** a backtest through `EditionRegeneration` over a window
containing posts produces an edition that cites every source, attributes
posts to their blog by name, and puts the essays on the reading list. A
judgement call read by a person, the way the PRD's own Milestone 0 was —
`lib/edition_transcript.rb` is the tool.

## Milestone 3 — the sources page

The first write UI in the app outside the waitlist and password reset.

- `resources :blogs, only: [:index, :create, :destroy]`, rendering into the
  Sources section the silencing branch builds rather than adding a fourth
  section beside it. One roster, one section — which is most of the
  argument for having a shared roster at all. If that branch has not landed,
  this milestone waits rather than building a section to be merged later.
- **The aggregator refusal lives on the add path.** Sample the feed on
  submission and decline one whose bodies are stubs, saying why: "this
  looks like a link aggregator; siftbox reads blogs". Refusing where the
  reader is standing is honest in a way silent exclusion at composition
  never is. What it says, and whether it can be overridden, are open.
- Feed autodiscovery from a pasted site URL (`<link rel="alternate">`) is
  the obvious nicety, and costs a second fetch through the same guard.
- Failed form renders return `422`, per `.claude/rules/controllers.md`, or
  Turbo ignores them.

Could swap with Milestone 2 — it is lower risk and makes Milestone 1
usable by someone other than whoever can open a console. It is second here
only because the editor is the app, and posts reaching it is the point of
the feature.

## Parked

Not scheduled. Each needs evidence first:

- **Full-text fetching** for truncated feeds, if the marker proves
  insufficient. A readability implementation and a new class of failure.
- **Silencing** — not parked so much as elsewhere: it is being built on
  `claude/mute-newsletters-reports-kh0rro`. Listed so this plan does not
  read as having forgotten it.
- **A per-blog cap**, if a subscription turns out busier than it looked.
- **Relaxing completeness for posts**, if volume ever makes it necessary.
- **A shared item table.** Option C, deferred rather than rejected: a third
  source type would multiply Option B's two id spaces rather than add to
  them, and that is the moment to extract one — with three concrete cases
  to design against instead of none.

## Deploy steps, collected

The things that do not install themselves:

| Milestone | Step |
|---|---|
| 1 | `gem "rss"` — and `rexml` joins the production bundle, where it is test-only today via `crack` under webmock. Note both in the commit message, per `.claude/rules/review.md` on dependency bumps. |
| 1 | Confirm the poll task registered: `SolidQueue::RecurringTask.all`, per `docs/deploying.md` §9. |
| 1 | Seed the reader's feeds by hand until Milestone 3 exists. |
| 2 | One additive migration on `edition_citations`. No backup needed — nothing is moved or dropped. |

## The risks worth naming

- **The merged ordering.** The likeliest bug in the whole plan, and a
  quiet one: a partial order over a merged set reorders rows between page
  loads and breaks the archive's continuous numbering. Every ordering in
  this app has a comment explaining its tie-break; the merged ones need
  theirs.
- **The first poll.** Get the recency guard wrong and a new subscription
  puts months of back catalogue into one edition window. It fails loudly —
  `Truncated`, or a request past the context window — but it fails on the
  morning the reader adds a blog.
- **SSRF through the shared fetcher.** `Destination` is the whole of what
  stands between a feed URL and the private network, and it is about to
  acquire a second caller. Its specs move with it, and the redirect path is
  the one to keep covered.
- **`VERSION` bumps in Milestone 2.** Editions are immutable and the
  version travels with the row, so this is the mechanism working. Listed
  because a version bump can look like a mistake in a changelog.
