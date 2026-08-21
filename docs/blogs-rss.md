# Investigation: blogs via RSS as a second source

The PRD parks this under Later in one sentence — "a second ingest path
writing a sibling of `Newsletter`; citations gain a second source type; the
edition's shape doesn't change" (`docs/briefing-prd.md`) — and leaves the
citation table as the seam. This is that sentence checked against the code
that now exists.

The finding, up front, in three parts:

1. **The reading half is already source-agnostic.** `Newsletter::Body`,
   `Newsletter::Prose`, `Newsletter::LeadImage` and
   `Newsletter::TrackingPixelScrubber` take an HTML string or a `Body` and
   know nothing about mail. They are misnamed, not mail-bound, so a second
   source type costs almost nothing on the rendering side.
2. **The fetch half is already built and hardened**, in the wrong class.
   `Newsletter::ImageDownload` plus its `Destination` is an SSRF-safe
   fetcher with a redirect ceiling, a byte cap, a wall-clock deadline and
   resolve-then-dial DNS-rebinding protection. A feed poller needs exactly
   that, for XML instead of images.
3. **The editor's exposure is a question of scope, not of engineering.**
   Measured against ten real feeds, aggregators produce 37 of 40 items a
   day with a median body of eight characters, and `Edition::Editor`
   demands a citation for every one — which breaks the edition outright.
   Excluding them (Decision 2, now decided) leaves eight real blogs
   producing **3.1 items and ~2,400 tokens a day**, and at that size the
   PRD's "the edition's shape doesn't change" is simply true.

So the recommendation is to stage it, to put a measurement first — the
same order Milestone 0 used for the editor itself — and to store the two
kinds of source under a **delegated type** rather than as two sibling
tables, because that is what keeps the third finding from becoming a
rewrite of the edition path.

## What is already there

Verified against the code rather than the PRD:

- **The citation seam.** `edition_citations` is a real table with its own
  row per (story, newsletter), exactly so a second source type can land
  here (`app/models/edition/citation.rb`).
- **A body-shaped rendering pipeline.** Nothing between `body_html` and the
  rendered page touches `Mail`. `Newsletter::Body` takes a string;
  `Newsletter::Prose` and `Newsletter::LeadImage` take a `Body`.
- **An SSRF-safe fetcher.** `Newsletter::ImageDownload::Destination`
  already takes a bare `URI` and answers with an address to dial. It is
  generic today; nothing in it mentions images.
- **A place for the roster to live.** The Subscriptions page was named for
  the page rather than the pen precisely so a Sources section could land
  there later (`app/models/subscriptions.rb`).
- **A recurring-task slot.** `config/recurring.yml`, production-only, with
  `compose_edition` already in it.

## What is not there, and is not free

- **`Newsletter::InboundMessage` is the only mail-bound class in the
  ingest path**, and a feed poller is its sibling, not its subclass. There
  is no shared superstructure to hang a second ingest path from, and there
  should not be one for two paths.
- **`Newsletter::RemoteImages` binds to the record**, not just to the
  markup, and it wants running over post bodies for the same reasons it
  runs over mail: the archive keeps its images after the blog's CDN forgets
  them, and opening a post tells the blog nothing. It asks the record for
  `body_html`, `inline_images`, `inline_image_path`, `transaction` and
  `update!` — a rename and a moved file rather than a rewrite.
  `Newsletter::InlineImages` is the one part of the pipeline a post has no
  use for at all: there are no MIME parts to rewrite `cid:` references
  from.
- **`Edition::Prompt::SCHEMA` names `newsletter_ids`** and nothing else,
  with `additionalProperties: false` doing real work. Any route into
  editions is a `VERSION` bump.
- **The completeness check is set arithmetic on newsletter ids**
  (`Edition::Editor#faults_in`). Two tables means two id spaces, and ids
  collide across them.

## Decision 1 — where a post is stored

### Option A: rows in `newsletters`

Store a feed item as a newsletter with a synthetic sender. Nothing
downstream changes: the archive, the window, the prompt, the completeness
check, the citations and the originals frame all work untouched, and the
prompt keeps `VERSION = "1"`.

Against it, and decisively:

- `sender_email` becomes a fabricated address, and it is not decorative —
  `Newsletter::Confirmation#first_time_sender?` keys off it. A blog whose
  first post through the feed is titled "Verify your backups" would be held
  in the pen as a subscription confirmation. That is a live bug on day one,
  not a tidiness complaint.
- `Subscriptions`' new-senders net fills with blogs, and that section
  exists to catch a subscription that never arrived.
- `message_id` would carry a `guid`, and the partial unique index that
  makes Postmark's retries idempotent would be doing double duty for feed
  dedupe, which has different rules (see Decision 3).

### Option B: a `blog_posts` table, sibling of `newsletters`

What the PRD says. The rendering pipeline is already generic, so the cost
lands almost entirely on the editor: two id spaces to keep apart, a window
merged in Ruby, and a completeness check that becomes two set comparisons
instead of one.

Citations gain a **second nullable foreign key**, not polymorphism:
`edition_citations.newsletter_id` stays, `blog_post_id` arrives, and a
check constraint says exactly one is set. Polymorphism would trade a
foreign key for a pair of untyped columns, and
`.claude/rules/database.md` asks for foreign key constraints with an
explicit `on_delete`. Two nullable keys keep both, keep
`belongs_to :newsletter` intact for every row that exists today, and read
honestly: there are two kinds of source, not an open set.

This is what the PRD describes, and it is the right answer only if the next
option is rejected: it accepts two id spaces, and every seam listed under
"What is not there" is somewhere that then has to learn about both.

### Option C: a delegated type — recommended

`delegated_type` is on Rails 8.1.3.1 and there is no polymorphism anywhere
in the app today, so this is a clean sheet. An `items` table holds what a
newsletter and a post have in common and points at whichever it is;
`newsletters` and `blog_posts` hold what only each of them has.

The split falls out of the code rather than needing to be invented, because
the reading pipeline is already generic:

| Table | Columns |
|---|---|
| `items` | everything the reading pipeline touches — `body_html`, `snippet`, `title`, `lead_image_url`, `source_name`, `received_at` — plus `itemable_type`/`itemable_id` and the `inline_images` attachment |
| `newsletters` | `message_id`, `sender_email`, `sender_name` |
| `blog_posts` | `blog_id`, `guid`, `url`, `published_at` |

What it buys is the whole of the cost centre Option B was accepting:

- **`Edition::Window` is one query**, not two relations merged in Ruby —
  and its `.or` across arrival and release keeps working as written.
- **`Edition::Editor#faults_in` is untouched.** Set arithmetic over one id
  space, which is the thing two tables break.
- **`Edition::Prompt::SCHEMA` keeps its shape**: `newsletter_ids` becomes
  `item_ids` and stays an array of integers. No prefixed ids, no second
  key, and `additionalProperties: false` goes on meaning what it means.
- **`Edition::Citation` gets one `belongs_to :item`** with a real foreign
  key and an `on_delete` — no nullable pair, no check constraint.
- **`Feed` is one query**, and `Edition::Story#newsletters` stays a single
  `has_many :through` with its `for_citation` scope intact.

`source_name` on `items` is the one denormalisation, and it earns its
place: `Newsletter::Presenter#sender` and `Edition::Story::Presenter#source`
both want a single display string, so putting it on the shared table keeps
the archive, the citations and the pen rendering off one table.
`FEED_COLUMNS`, `CITATION_COLUMNS` and `PEN_COLUMNS` exist because bodies
run to hundreds of kilobytes; without `source_name` they would each need
`includes(:itemable)`, which is a polymorphic preload — a query per type —
and the citation list would be back to loading newsletters to print names.

### What the delegated type costs, stated honestly

- **The polymorphic column does not disappear, it relocates.**
  `items.itemable_type`/`itemable_id` carries no foreign key, which was the
  objection to polymorphic citations above. It lands where it matters less:
  the edge that must never dangle is citation → item, and that edge gets a
  real constraint. But `.claude/rules/database.md`'s "foreign key
  constraints with an explicit `on_delete`" is still not satisfied
  everywhere, and saying otherwise would be a dodge.
- **The pen has to choose a side.** `Feed` and `Edition::Window` filter on
  `Newsletter.content` *and* on `received_at`. With `received_at` on `items`
  and `held_at`/`dismissed_at`/`released_at` on `newsletters`, the app's two
  hottest queries become joins with an OR across types. The fix is to hoist
  the three timestamps onto `items` — and that is less of a compromise than
  it first looks: the pen's meaning is "is this the reader's to read",
  which is an item-level question. Only its *trigger* is mail-specific, and
  `Newsletter::Confirmation` reads a subject and a sender and writes
  nothing, so it stays exactly where it is. Silencing, when it lands, wants
  both types anyway.
- **`Newsletter::EARLIEST_FROM_SENDER` gets rewritten.** The correlated
  `NOT EXISTS` with the row-value comparison on `(received_at, id)` spans
  both tables once `received_at` moves, and the tie-break reasoning has to
  be re-derived against `items.id`. It is one query, it is carefully
  reasoned, and it will need re-reasoning rather than translating.
- **The migration touches every row the reader has.** An `items` row per
  newsletter, and `edition_citations.newsletter_id` repointed. Published
  editions' `raw_response` then names ids in a namespace that no longer
  exists — tolerable, because `EditionRegeneration` recovers a window "from
  its citations rather than from the dates on the row", so the citations
  are the authority and `raw_response` stays archival. Worth writing into
  the migration, and worth a backup before the staging and production
  deploys per `.claude/rules/review.md`.
- **`subject` and `title` unify.** One column on `items`; `title` is the
  general word and `subject` is mail's. A small rename across views and
  locales.
- **Two inserts per ingest**, inside the transaction
  `Newsletter::InboundMessage#store` already opens. Cheap.

### Option D: a `Source` model first

The PRD's silencing entry says that is the moment "sender" stops being a
string column, and that per-sender hints and RSS both want it. True, and
still the wrong order: silencing is a feature for the reader, RSS is a
second ingest path, and doing the refactor first means designing the
abstraction against one real user of it. Do C, then let a `Source` fall
out of the two concrete cases if it wants to.

### Option E, named so it can be rejected: fabricate email

Poll the feed, build a `Mail` message from each item, and post it through
`NewslettersMailbox`. Cheapest possible path, reuses everything including
dedupe. Rejected: `Newsletter::InboundMessage` is careful in the way it is
because real newsletter MIME is messy, and every one of those guards would
be reading a message this app itself wrote a moment earlier. It buys reuse
by making the most carefully-reasoned file in the ingest path parse a
fiction.

## Decision 2 — how the editor survives feed volume

**Decided: aggregator feeds are out of scope.** Hacker News, lobste.rs,
Reddit, Planet-style rollups. A feed whose items carry no body of their own
is a list of links, not a source, and the measurement below is what settled
it. Everything else in this section follows from that.

It was measured rather than reasoned about. Ten real feeds were fetched and
every item run through the app's own `Newsletter::Body` and
`Newsletter::Prose` — the same two passes `Edition::Prompt#prose` makes —
so the character counts are what the editor would actually be handed.

### Why aggregators are out

The two aggregator feeds produced **37 of the 40 items published in a
day**, with a median body of **eight characters**. This is an unedited
Hacker News item as `Newsletter::Prose` hands it over:

```
title: "DeepSeek-v4-flash-vision-exp"
prose: "Comments"
```

That is the whole body — the word "Comments", because an aggregator's
`<description>` is a link to its own thread. `Edition::Prompt` would quote
each of the 37 as a source, and `INSTRUCTIONS` then requires three things
that cannot all hold for such an item:

- "Every newsletter gets cited by at least one story — a dull one earns a
  deadpan line in briefly, not silence."
- "Report only what the sources say. You have no other knowledge of these
  events."
- "Invent nothing: no links, no figures, no quotes, no names that are not
  in the sources."

Cite it, write it from the source alone, invent nothing — from a headline
and the word "Comments". All three outcomes are bad. It complies, and the
edition is 37 deadpan lines restating 37 headlines. It drops one, and
`Edition::Editor#uncited` fires, three attempts go out against the
identical memoised prompt, `Incomplete` is raised, and
`Edition::CompositionJob`'s `discard_on` gives up — **no edition that
morning**. Or it fills the gap from memory, and a claim in the edition is
no longer supported by the source beside it, which is the one failure the
citation guarantee exists to make impossible.

The middle case compounds: `Edition.watermark` is
`maximum(:window_ended_at)` over *published* editions, so a discarded
composition does not move it. Tomorrow's window is 48 hours and 80
aggregator items, and it fails harder. Nothing recovers on its own.

No cap fixes this. A cap of three per feed still hands the editor three
items reading "Comments". The shape is wrong, not the volume, which is why
the answer is scope rather than a setting.

### What the in-scope feeds actually look like

The remaining eight — Julia Evans, Dan Luu, Simon Willison, the Rust blog,
Martin Fowler, DHH, the GitHub blog, Coding Horror — are a different
animal entirely:

| | last 7 days | last 30 days |
|---|---|---|
| items | 22 | 57 |
| per day | **3.1** | **1.9** |
| prose after `Newsletter::Prose` | 68,453 chars | 205,547 chars |
| tokens per day | **~2,400** | **~1,700** |

Real blogs publish *rarely*. Of the eight, four had published nothing in
the week measured; Simon Willison's link blog alone accounted for 14 of the
22. Eight subscriptions produce about three items a day, at around two
thousand tokens — against a newsletter window the PRD assumes at 60k.

**So with aggregators excluded, this decision mostly dissolves.** Three
extra sources a day is not a completeness problem, not a token problem, and
not a `MAX_TOKENS` problem. The PRD's "the edition's shape doesn't change"
turns out to be right *once the scope is right* — which is the opposite of
what an earlier draft of this document concluded, and the measurement is
what changed it.

### What is still worth doing

1. **Enforce the scope where the reader can see it.** Out-of-scope is a
   policy, and policies that live only in a document get violated by the
   person who wrote them. The sources page is the place: on adding a feed,
   sample its items and refuse one whose bodies are stubs, saying so —
   "this looks like a link aggregator; siftbox reads blogs". Refusing at
   add time is honest in a way silent exclusion at composition never is,
   and it is the only moment the reader is present to be told.
2. **A prose floor, demoted to a cheap guard.** Legitimate blogs still
   carry the odd stub: 9 of the 273 in-scope items came in under 400
   characters — Martin Fowler publishes an essay in linked fragments, and
   Simon Willison posts release notes. Small enough that it is no longer
   the fix, big enough to be worth one predicate. It is this app deciding
   an item is not worth reporting, so it should say so out loud rather than
   dropping quietly.
3. **A per-blog cap, demoted further.** At 3.1 items a day nothing is
   crowding anything out. Worth keeping in mind for the day a subscription
   turns out to be busier than it looked, not worth building now —
   `.claude/rules/ruby.md` on not writing code for functionality that does
   not exist yet.
4. **Expect the reading list to absorb them.** Most of these are evergreen
   essays, so they land in `reading_list`, where the prompt already asks
   for a review rather than a summary. Blogs may make the reading list the
   biggest section of the edition, which is arguably the product working.

The one thing the scope decision does *not* fix is the first poll — Dan
Luu's feed alone is 128 items of back catalogue. See Decision 4.

## Decision 3 — what identifies a post, and what "seen before" means

Newsletters dedupe on `message_id` behind
`index_newsletters_on_present_message_id`, and ingestion has to be
idempotent because Postmark retries ten times over six hours. Polling has
the same requirement for a different reason: every poll re-reads items it
has already stored.

Feeds are worse-behaved than mail here:

- `<guid>` (RSS) and `<id>` (Atom) are the analogue, but a `guid` is not
  guaranteed present, not guaranteed a permalink, and not guaranteed
  stable — some publishing tools rewrite it when a post is edited.
- Two blogs can emit the same `guid`. Scope uniqueness to the blog rather
  than making it global: `unique on (blog_id, guid) where guid <> ''`,
  which is the same partial-index shape the newsletters table already uses.
- With no `guid`, fall back to the item's link, then to a digest of title
  plus published date. Say so in the column comment; a fallback nobody
  wrote down is a fallback nobody trusts later.

**Edits are the interesting case.** A newsletter never changes after it is
sent. A blog post changes whenever the author fixes a typo or rewrites a
paragraph. Recommendation: **first fetch wins, and updates are ignored.**
A citation is a promise that the claim beside it can be checked against
what was read; silently swapping the body out from under a published
edition breaks that promise in the one place the app has said it will not.
If revisions later prove worth having, they are a new row, not a mutated
one.

## Decision 4 — what time a post arrived

`Edition::Window` runs on `received_at`, and for mail that is the sender's
`Date` header. For a polled item, two candidates, both wrong on their own:

- **The feed's `pubDate`.** Honest about when the post was published, and
  it puts every item of a newly-added feed *below* the watermark, where no
  edition will ever cover them. They would appear in the archive and never
  in an edition — a silent drop.
- **The moment we fetched it.** Puts a newly-added feed's entire back
  catalogue — often twenty items, sometimes months of it — into one
  window, at once. `Edition::Window::FIRST_WINDOW` exists because exactly
  this happened to the archive when editions were first switched on.

**Store both.** `published_at` is the feed's claim and is what the archive
sorts and displays by; `received_at` is when this app first saw the item
and is what the window runs on, so the edition axis stays a single
consistent clock across both source types.

Then close the back-catalogue case explicitly, the way `FIRST_WINDOW`
does: **the first poll of a new blog admits only items published inside a
bounded recency window**, and records the rest with a `received_at` that
is deliberately behind the watermark, or does not record them at all. My
preference is to store them — the archive is better for having them and
the reader may want to browse what they just subscribed to — and to keep
them out of the window by publication date on that first poll only. It
wants to be one clearly-named method with the reasoning above it, not an
incidental `.limit`.

The measurement puts a number on why. The ten feeds carry **328 items**
between them, and unbounded that is **520,000 tokens** of prose — roughly
two and a half times the model's context window. A first poll with no guard
does not produce an expensive edition, it produces a request that cannot be
made at all. Dan Luu's feed is 128 of those items on its own, because it
carries the entire archive with no truncation.

## The fetch

Reuse, with one extraction:

- **`Newsletter::ImageDownload::Destination` moves up as-is.** It takes a
  URI and answers with an address to dial, checks every address a name
  resolves to rather than just the one it will use, and unmaps
  IPv4-in-IPv6. Nothing in it is image-specific. Feed URLs are typed by the
  reader rather than sent by strangers, which sounds like it lowers the
  stakes and does not: a blog can redirect to `169.254.169.254`, and the
  redirect is followed by this app from inside its own network.
- **`Newsletter::ImageDownload` splits.** Everything except `renderable?`
  and the `Image` shape is generic: `MAX_REDIRECTS = 3`, `TIMEOUT = 5`,
  `MAX_DURATION = 20`, the `FAILURES` list, the streamed body with a byte
  cap checked against both `Content-Length` and the actual bytes. A feed
  fetch wants all of it with a different content-type allowlist and its own
  size ceiling.

New concerns that images did not have:

- **XML parsing of a stranger-controlled document.** Entity expansion
  (billion laughs) and external entities. Tested, and safe by default under
  the recommended parser — see Parsing — but safe *by default* is the
  operative phrase: it wants restating explicitly with a spec pinning it,
  rather than inherited from a REXML default that a later Ruby could
  move.
- **A size cap that is not the image cap, and is bigger.** This was
  guessed wrong first time: `Newsletter::ImageDownload::MAX_BYTES` is 5MB,
  and Dan Luu's Atom feed measured **11.2MB** — a legitimate feed from a
  well-known blog, silently refused by a borrowed ceiling. Feeds carry
  archives where images carry one picture. The cap has to be chosen for
  feeds and it has to be generous, which makes the streaming byte check in
  `ImageDownload#capped_body` more load-bearing here than it is there.
- **Conditional GET.** Store the blog's `ETag` and `Last-Modified` and send
  them back. Polite, and it makes an hourly poll nearly free for the
  publisher. Store `Last-Modified` as the header string verbatim rather
  than as a datetime — servers compare it as text, and a re-emitted
  timestamp is a good way to get a 200 every time. That is a deliberate
  exception to the `_at` naming convention and wants naming as one.

## Parsing

**Recommend `rss` (ruby/rss), wrapped in one adapter.** It was tried
against the eight in-scope feeds rather than chosen on paper, and it earns
the choice:

| | |
|---|---|
| feeds parsed | **8 of 8**, in *strict* mode — `validate: false` was not needed |
| formats | RSS 2.0 and Atom, both reached through `feed.items` |
| Dan Luu's 11.2MB feed | parsed in **1.38s**, the slowest by an order of magnitude |
| dates | come back as real `Time` objects, RFC-822 and ISO-8601 alike |

The dates are the quiet win, and they are one of the three reasons not to
hand-roll this on Nokogiri. The other two — format sprawl and namespace
handling — it also absorbs.

**Its XML security posture is good by default**, which was an open worry in
the fetch section above and is now closed. Backed by REXML, whose defaults
are `entity_expansion_limit = 10000` and `entity_expansion_text_limit =
10240`:

- **Billion laughs: refused.** A six-level bomb that would expand to 10
  million characters comes back as
  `RSS::NotWellFormedError: number of entity expansions exceeded`.
- **External entities: not resolved.** A `<!ENTITY x SYSTEM
  "file:///etc/hostname">` reference comes back as the literal string
  `&x;`.

Both are defaults rather than settings this app chose, so they want
restating in the adapter with a spec pinning them — a REXML default that
moves in a later Ruby would move this app's XXE posture with it, silently.

**What the wrapper is actually for.** The collection is uniform — `items`
works on both — but the fields are not, and this is the whole of the
difference:

| | RSS 2.0 | Atom |
|---|---|---|
| title | `title` | `title.content` |
| identity | `guid.content` | `id.content` |
| body | `content_encoded` \|\| `description` | `content.content` \|\| `summary.content` |
| date | `pubDate` | `published.content` \|\| `updated.content` |

That is a fifteen-line normaliser, not a rewrite, and it keeps the parser
choice revisitable without touching anything else.

**Two things to get right when adopting it:**

- **It is a bundled gem, not a default one.** `require "rss"` raises
  `LoadError` under Bundler on the pinned 3.3.6 until `gem "rss"` is in the
  `Gemfile`, and declaring it pulls `rexml` into the production bundle,
  where it is currently a *test-only* transitive dependency via `crack`
  under webmock. Both belong in the commit message per
  `.claude/rules/review.md` on dependency bumps.
- **Feed bytes must be read as UTF-8 explicitly.** Handing the parser a
  string tagged US-ASCII fails every feed in this set with
  `ArgumentError: invalid byte sequence in US-ASCII` — which is exactly the
  class of problem `Newsletter::InboundMessage#utf8` already exists to
  solve for mail, arriving on the other ingest path. A feed declares its
  encoding twice (the XML declaration and the HTTP `charset`) and the two
  can disagree or both be missing, so this wants deciding once, in the
  fetch, rather than at the parse.

The alternatives, for the record: **Feedjira** normalises the formats for
you but is a new dependency with its own chain, for an app whose `Gemfile`
is deliberately short — and the table above shows the normalising is
fifteen lines. **Nokogiri directly** is already in the production bundle
through Loofah, but hand-rolling feed parsing is a classic underestimate,
and it would mean owning the date parsing and the entity limits that `rss`
hands over for free.

**The partial-feed problem is worth calling out separately, and the
measurement sharpened it.** The obvious detector — the body arrived in
`<summary>`/`<description>` rather than `<content>`/`content:encoded` — does
not work. Dan Luu's feed puts *full articles* in `<summary>`: 128 items,
median prose 11,997 characters, 22 of them hitting the 12,000 cap. Simon
Willison's feed is also all `<summary>`, median 1,169 characters, and those
short ones are mostly link posts that are short by design rather than
truncated. So which element carried the body says nothing, and length alone
cannot separate "truncated" from "briefly, on purpose". Any rule here is a
heuristic, and it should say so out loud the way
`Newsletter::Confirmation` does.

The shape of the problem is unchanged: many blogs publish a two-line
`<description>` and no `content:encoded`. The editor
would read that as the PRD's *teaser* nature and report it as paywalled —
"the free portion covers X; the rest is paywalled" — which is a falsehood
about a blog that simply publishes summary feeds. Two ways out: fetch the
linked page and extract the article (a second fetch, a readability
implementation, and a new failure mode), or mark the truncation honestly in
the prose the editor is shown, the way `Newsletter::Prose::OMISSION`
already names this app's own cut. The second is nearly free and precise:
a marker line saying the feed carried a summary only, so the editor reports
a stub as a stub and links to it. Do that first, and treat full-text
fetching as a later step justified by how many feeds turn out to need it.

## Reading surfaces

- **The archive.** `Feed` groups `Newsletter.content` by day over a 7-day
  window; posts want to appear in the same list. Two queries merged in
  Ruby is fine at this size and keeps both tables' scopes honest — the
  page already loads its whole window into memory to partition it.
  `Feed::Row` and the `newsletters/_row` partial take a presenter, so a
  post needs a presenter answering the same handful of methods rather than
  a second partial.
- **"View original".** For mail this is the sandboxed frame around the
  sender's own HTML, and `Newsletter::Source` embeds inline images as data
  URIs because the frame has an opaque origin. A post has no inline images
  — no MIME parts — so that whole mechanism is a no-op, and the *real*
  original is the blog's own URL, always present in the feed item. A post's
  "view original" should be an external link, which is simpler than the
  mail case and also the PRD's parked "canonical web links" idea arriving
  for free on one source type.
- **A sources page.** Adding a feed is the first write UI in the app
  outside the waitlist and password reset. It belongs on Subscriptions,
  which was named for that. Resourcefully: a `blogs` resource with
  `only: [:index, :create, :destroy]`, rendered as a section of the
  Subscriptions page.

## Naming

Three of the obvious words are taken, and this is worth settling before
any file is written:

- **`Feed`** is `app/models/feed.rb` — the archive index's collection.
- **`Newsletter::Source`** is the sender's HTML for the sandboxed frame.
- **`Source`** is also a Struct inside `Edition::Story::Presenter`, for a
  citation on the page.

So the PRD's "`Source` concept" cannot be called `Source` without a rename
of two existing things. Proposed instead, using the reader's own word:

| Class | What it is |
|---|---|
| `Blog` | The subscription: title, feed URL, site URL, polling state |
| `Blog::Post` | One stored item |
| `Blog::Feed` | The fetched, parsed document — namespaced, so no collision |
| `Blog::Feed::Item` | One normalised entry, whatever format it arrived in |
| `Blog::Poll` | One visit to a feed, with `#save`, mirroring `Newsletter::InboundMessage` |
| `Blog::PollJob` | One blog, polled off the request path |

`Blog::Poll#save` deliberately echoes `InboundMessage#save`: the two are
the same job — read a thing from outside, store what is new, be idempotent
about what is not — and the parallel is worth being able to see.

## Schema sketch

For discussion, not a migration, in the PRD's phrasing, and under Option C:

- `items` — `itemable_type`, `itemable_id`, `title`, `body_html`,
  `snippet`, `lead_image_url`, `source_name`, `received_at`, and the pen's
  `held_at`/`dismissed_at`/`released_at`. `has_many_attached
  :inline_images` moves here with them. Index `received_at`; keep the two
  partial indexes the pen already has, and re-check `Edition::Window`'s
  `EXPLAIN QUERY PLAN` note against the moved columns rather than assuming
  it still holds.
- `newsletters` — reduced to `message_id`, `sender_email`, `sender_name`,
  keeping `index_newsletters_on_present_message_id` exactly as it is: that
  index is what makes Postmark's ten retries idempotent, and it should not
  move or change shape in the same migration that moves everything else.
- `blog_posts` — `blog_id` (FK, `on_delete: :cascade`), `guid`, `url`,
  `published_at`. Partial unique index on `(blog_id, guid) where guid <> ''`,
  the same shape the newsletters table already uses.
- `blogs` — `title`, `feed_url` (unique), `site_url`, `polled_at`, `etag`,
  `last_modified_header`, `failing_since`, and `silenced_at` if silencing
  lands at the same time. Optional strings default to `""` per
  `.claude/rules/database.md`.
- `edition_citations` — `newsletter_id` becomes `item_id`, with a foreign
  key and an `on_delete`. One key, not two, and no check constraint.

The pen sits on `items` rather than on `newsletters` for the reason given
under Option C's costs: its meaning is item-level even though only mail
triggers it today. `Newsletter::Confirmation` does not move — it reads a
subject and a sender and writes nothing, so it stays the mail-only detector
it already is.

## Staging

- **Stage 0 — measure, store nothing.** *Partly done: the numbers under
  Decision 2 and Decision 4 come from exactly this, run by hand against ten
  real feeds.* What is left is to make it a development rake task and point
  it at the reader's own feed list rather than a plausible one, over
  several days rather than one snapshot, so the prose floor is tuned
  against what it will actually see. The one snapshot settled the
  aggregator scope, corrected two numbers in this document and reversed one
  of its conclusions, which is the argument for doing the rest of it before
  Stage 1.
- **Stage 1 — the delegated type, with one type.** Introduce `items`, move
  the shared columns and the pen onto it, repoint `edition_citations`, and
  leave `Newsletter` as the only `itemable`. No feeds, no posts, no new
  behaviour: a refactor whose entire success condition is that the suite
  and `bin/ci` are as green afterwards as before. Doing it alone is what
  makes it reviewable — every later stage is additive against a shape that
  has already been proved against the reader's real archive.
- **Stage 2 — fetch and store.** `Blog`, `Blog::Post` as the second
  `itemable`, the poller, the recurring task, dedupe, the first-poll guard,
  and posts in the archive. Editions untouched. Shippable on its own:
  nothing already published is affected.
- **Stage 3 — the sources page.** Add and remove a feed from Subscriptions,
  with the aggregator refusal from Decision 2 living on the add path — the
  one moment the reader is present to be told why a feed was declined.
  Until the page exists, feeds are seeded by hand, which is fine for one
  reader. Feed autodiscovery from a pasted site URL
  (`<link rel="alternate">`) is the obvious nicety and costs a second fetch
  through the same guard.
- **Stage 4 — into editions.** The prompt gains `<post>` elements and
  `newsletter_ids` becomes `item_ids`; `Edition::Prompt::VERSION` goes to
  2; the prose floor goes in. `Edition::Window`, `Edition::Editor` and
  `Edition::Citation` need no structural change, which is the whole return
  on Stage 1 — and at ~3 items a day the completeness guarantee needs no
  relaxing either.
- **Stage 5 — the follow-ups.** Full-text fetch for summary feeds if
  Stage 0 says enough of them need it; silencing; caps tuned against real
  editions.

The trade against Option B is worth being explicit about. A sibling table
would let Stage 2 ship first and leave the existing schema alone, so the
blast radius stays small until the feature has proved itself. The delegated
type front-loads a migration over every row the reader has, before a single
post is stored — and buys back a Stage 4 that changes a prompt and a
column name rather than every query in the edition path.

## Deploy

Per `.claude/rules/review.md`: a new scheduled task needs a deploy step and
does not install itself. Polling goes in `config/recurring.yml` alongside
`compose_edition`, production-only for the same reason, with a line in
`docs/deploying.md`. Hourly is ample — the window picks up whatever has
arrived since it last closed, so polling cadence only decides how stale an
item can be when the edition is composed, and an hour against a daily
edition is noise. `spec/config/recurring_spec.rb` is what checks the line.

## Not proposed

- OPML import. One reader, a dozen feeds, typed once.
- WebSub/PubSubHubbub push. A subscription callback endpoint, a
  verification handshake and a public URL, to save an hourly GET.
- Read/unread state, per-feed schedules, favicons, comment feeds.
- Revisions of a post, per Decision 3.
- A `Source` abstraction over blogs and senders, per Decision 1D — let it
  fall out of two concrete cases rather than designing it now. A delegated
  type makes it easier later, which is a reason not to reach for it now.
- **Aggregator feeds** — Hacker News, lobste.rs, Reddit, Planet rollups.
  Decided out of scope in Decision 2, on the measurement. siftbox reads
  sources, and a list of links is not one.

## Open questions

1. **Does completeness hold for posts?** Every newsletter in a window earns
   a citation. Should every blog post? A post is public and permanent where
   mail is delivered once, which is the strongest argument the guarantee
   has for treating them differently. Less pressing now that the scope
   decision has taken the volume out of it, but still the reader's promise
   to change rather than an implementer's.
2. **Where is the aggregator rule enforced, and how does it read?** The
   scope is decided; the mechanism is not. An add-time check on the sources
   page that samples a feed and refuses a stub-bodied one is the proposal —
   what it should say when it refuses, and whether it can be overridden,
   are the open parts.
3. **Do truncated feeds get full-text fetching, or an honest marker?** The
   marker is nearly free; the fetcher is a readability implementation and a
   new class of failure. Note from the measurement that "truncated" has no
   reliable detector — see Parsing.
4. **Does a post's "view original" leave the app?** It is the only honest
   original a post has, and it is the first outbound link the reading
   surfaces would carry.
5. **Is the delegated type worth its migration before the feature has
   proved itself?** Option C buys a final stage that changes a prompt and a
   column name instead of every query in the edition path, and pays for it
   with a migration over every row the reader has, run before a single post
   exists. Option B inverts both. The recommendation is C on the grounds
   that the edition path is the part that is hard to change twice — but it
   is a judgement about appetite for a schema migration, not a technical
   fact, and it is the reader's to make.
