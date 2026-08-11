# PRD: Editions — a twice-daily briefing

v2, after review. The shape questions from the first draft are now decided:
story-first editions, an edition-first app, the inbox demoted. What remains
**Open** is marked. The app is a prototype with one user, so nothing here
carries a backwards-compatibility burden.

## The idea

siftbox today is a newsfeed: every newsletter arrives as a row, and the
reader triages and reads each one individually. The model to move to is The
Week:

> a news digest that does almost no original reporting. Editors read a large
> volume of newspapers, magazines and websites, then condense that coverage
> into short summaries, deliberately drawing on outlets from across the
> spectrum.

Here, the newsletters (and later, blogs via RSS) are the original reporting.
An AI editor reads everything that arrived since the last edition, works out
what the stories are, and writes them up with attribution. The edition — not
the inbox — is the app.

Two editions a day:

- **Morning edition**, 07:00 Europe/London — covers the overnight window,
  when US newsletters land. Starting time; adjust once real editions show
  the senders' actual rhythm.
- **Afternoon edition**, 15:00 Europe/London — covers the day so far,
  catching US morning releases.

## Jobs to be done

1. **Catch me up.** When I open the app, tell me what mattered across all my
   newsletters since I last looked, without me triaging each email.
2. **Collapse duplicate coverage.** When four newsletters cover the same
   story, I want one write-up that notes the differing angles — read it
   once, not four times. This is where an edition beats per-email TL;DRs.
3. **Route me to the good stuff.** The edition is a router, not a
   replacement. When something deserves a full read, the edition links me to
   the original.
4. **Absorb my absence.** After a weekend away, one catch-up read — not
   thirty unread rows.
5. **Keep the archive honest.** Originals remain stored and reachable.
   Every claim in an edition traces to a source I can open.

## Decisions

### Story-first editions

The unit of an edition is the **story**, not the newsletter. The editor
reads the window, extracts the stories each newsletter covers, clusters
them across sources, and writes each one up with attribution — "Money Stuff
and The Diff both read the Figma S-1; Levine focuses on…". A newsletter
that covers five topics contributes to five stories; five newsletters on
one topic collapse into one.

Presentation has two tiers, but they are the same thing at different
lengths:

- **Lead stories**: the day's few significant threads, a paragraph each.
- **Briefly**: minor stories in a line or two. A singleton story from one
  source lands here naturally — so quiet days degrade gracefully rather
  than forcing fake syntheses.

This is the hardest version of the prompt problem, chosen deliberately.
The fallback, if testing shows clustering isn't reliable enough, is the
hybrid shape from v1 of this document (synthesised leads over per-source
briefs). See "Proving the bet".

### Completeness is a hard guarantee

Every newsletter in the window is cited by at least one story. This is
validated mechanically against the model's output — regenerate on failure —
not hoped for in the prompt. It was important before; now that the edition
is the *only* triage surface (below), it is load-bearing. A dull promo
email becomes a one-line singleton in Briefly; that is the floor that makes
"nothing can be missed" true.

### The edition is the app; the inbox is demoted

- Signed-in root serves the latest edition. Edition archive at
  `resources :editions, only: [:index, :show]`.
- Story citations link to the **original** — the existing in-app original
  page (sandboxed iframe of the sender's HTML). Extracting the
  newsletter's own "view in browser" URL and linking out to the live web
  version is a possible later refinement.
- **Read state is retired.** No unread counts, no read filter, no
  mark-as-read — triage is the edition's job now. Drop the UI and the
  `reads` route; the column can linger or go in a cleanup migration.
- The feed survives only as a plain **archive** of originals (a list, by
  day, as now, minus read state). It earns its place three ways: verifying
  ingestion ("did this morning's Money Stuff arrive?"), finding something
  weeks later outside any edition, and auditing the editor ("what did the
  edition have to work with?"). If living with editions shows nobody
  visits it, delete it then — cheap to keep, cheap to kill.

### Windows: high-water mark, not fixed ranges

An edition covers newsletters received after the previous edition's
cutoff, up to the moment composition starts. No fixed 15:00→07:00 ranges:
with fixed windows, a failed run or an email landing at 07:02 falls into a
gap and is never covered. With a watermark, every newsletter belongs to
exactly one edition, whichever runs next. `received_at` (already indexed)
is the clock; anything arriving mid-composition belongs to the next
edition.

### Empty windows skip silently

No newsletters since the last cutoff → no edition. The home page shows the
most recent edition regardless of age, its timestamp doing the honesty
work.

### Masthead and numbering

Editions number their own sequence from **No. 1**, independent of the
feed's issue numbering. "Morning edition · No. 1" — JetBrains Mono's job,
per `docs/siftbox-redesign.md`.

### Delivery: web only for v1

Editions live in the app. Emailing the edition to the reader's own address
and a private RSS feed of editions are natural later steps — Future, not
v1.

## Requirements

### Functional

- Compose an edition at 07:00 and 15:00 Europe/London on a schedule (Solid
  Queue recurring task; scheduled in the zone so DST never moves it). Per
  `.claude/rules/review.md`: a scheduled task is a deploy step and must be
  called out in the deploy docs.
- An edition records: slot (morning/afternoon), published time, the window
  covered, its stories in order, and which newsletters each story cites.
- Every newsletter in the window cited at least once, mechanically
  validated; regenerate on failure, fail loudly (log) if it won't converge.
- Edition page: masthead, lead stories with attribution links to
  originals, then Briefly. One edition per slot per day, unique index.
- Root serves the latest edition; archive of editions; archive of
  originals at `/newsletters` stripped of read state.
- A failed run retries; a morning edition composed late is still the
  morning edition (labelled by slot, not wall clock).

### AI editor

- Input: per-newsletter plain text extracted from `body_html` — stripped
  of newsletter chrome (subscribe prompts, "read in app", social icons,
  footers; the ingest pipeline already scrubs tracking pixels) and capped
  per source — plus sender, subject, received time.
- Output: structured JSON — stories with headline, body, tier, and cited
  newsletter ids — never free-form HTML. Rendered through normal ERB
  escaping; the model's words get no `html_safe` path, ever
  (`.claude/rules/security.md`).
- Stored alongside the edition: model name, prompt version, token counts,
  raw response — enough to debug a bad edition and regenerate after a
  prompt change without re-fetching anything.
- Editorial constraints in the prompt: report only what the sources say;
  attribute claims to their newsletter; where sources disagree, say so
  rather than resolving it; no outside knowledge, no invented links;
  cluster before writing — one story per underlying event, however many
  sources touched it.
- Cost envelope: ~10–20 newsletters × a few thousand tokens, twice daily —
  tens of cents a day on a mid-tier model. Not a constraint at one reader;
  a line item in any public-release thinking.

### Non-functional

- Composition is a background job; nothing in the request path calls the
  model. A reader mid-morning sees the last published edition, never a
  spinner.
- API key in credentials. Failures surface in logs; one reader will notice
  a missing edition anyway.
- Tests stub the model client with a fake (`.claude/rules/testing.md`:
  prefer a fake object over stubbing HTTP; WebMock blocks the rest).

## Proving the bet

Story-first is chosen to be tested, and there is real data to test on:
weeks of already-ingested newsletters. **Milestone 0, before any schedule
or UI:** a dev task that composes an edition from a chosen historical
window and dumps it for reading. Judge, by hand, over several windows:

- **Clustering** — did one event become one story? No duplicates, no
  false merges of unrelated items?
- **Attribution** — is every claim traceable to the cited newsletter, and
  accurate against it?
- **Coverage** — does the citation validation pass, and does Briefly read
  as useful lines rather than filler?
- **Selection** — are the leads the pieces the reader would have picked?

Iterate the prompt against real windows until these hold, then build the
schedule and pages around it. If clustering won't converge, fall back to
the v1 hybrid shape — the schema below supports either.

## Data model sketch

For discussion, not a migration:

- `editions` — `slot`, `published_at`, `window_started_at`,
  `window_ended_at`, `model`, `prompt_version`, `raw_response`. Unique on
  (date of publication, slot).
- `edition_stories` — `edition_id`, `position`, `tier` (lead/brief),
  `headline`, `body` (plain text/markdown).
- `edition_citations` — `edition_story_id`, `newsletter_id`. The joint
  where RSS items later plug in as a second source type — not building
  polymorphism now (`.claude/rules/ruby.md`: no code for functionality
  that doesn't exist), but keeping citations a real table leaves the seam.
- Domain objects per `.claude/rules/models.md`: `Edition`,
  `Edition::Editor` (a noun — composes an edition from a window,
  `#compose`), `Edition::PublishJob`. No `*Service`.

## Edge cases

- **Huge bodies**: newsletters run to hundreds of KB of HTML. Text
  extraction plus a per-source cap bounds the prompt; a catch-up window
  after downtime that still overflows gets chunked by source and composed
  in two passes.
- **Link-roundup newsletters** (e.g. AINews): less a special case under
  story-first than under summarisation — their items are simply more
  story candidates, and notable ones cluster with other sources' coverage.
  Whether their long tails pollute Briefly is a Milestone 0 observation.
  Per-sender handling hints are deferred (see Later).
- **Non-newsletter mail** to the ingest address (receipts, spam): today it
  lands in the feed; in an edition it becomes a deadpan Briefly line. An
  existing problem made louder; out of scope here.
- **Model hallucination**: structured output + citation validation + the
  original one click away. The edition never needs to be trusted further
  than its links.
- **Prompt iteration**: editions are immutable once published; prompt
  changes apply from the next edition. A dev-only regenerate task is fine
  (and is Milestone 0's tool anyway).
- **DST**: schedule in Europe/London so 07:00 means 07:00 all year.

## Assumptions

- One reader, one global timeline — editions, like `Feed`, are unscoped
  behind the authentication gate. Multi-user means per-user editions, N×
  model cost, per-user schedules; acknowledged and deferred, as in the
  README's note on multiple users.
- English-language sources.
- The model API is reachable from production; latency of tens of seconds
  is fine in a background job.
- Twice-daily is a starting cadence. Slots + watermark don't care if it
  becomes once or thrice daily.

## Non-goals for v1

- Blogs / RSS ingestion (the citation seam is left ready).
- Email or RSS delivery of editions.
- Per-sender prompt hints, including special handling for link-roundup
  newsletters.
- Personalisation, feedback ("more like this"), topic weighting.
- Search, audio, multi-user, public sign-up.
- Any change to ingestion.

## Success measures

Honest ones, at n=1:

- Milestone 0's four checks (clustering, attribution, coverage,
  selection) hold across several real windows before launch, and keep
  holding after.
- The edition is the only surface the reader needs day to day; the
  originals archive is visited for reference, not for triage.
- Click-throughs feel right — the editor routes to the pieces the reader
  would have picked anyway.
- A month in, no edition has misattributed or invented a claim that the
  citation links exposed.

## Later

- **Per-sender hints** for link-roundup newsletters, if Milestone 0 shows
  they need different treatment.
- **Canonical web links**: extract the sender's own "view in browser" URL
  and offer the live web original alongside the stored one.
- **RSS/blog sources**: a second ingest path writing a sibling of
  `Newsletter`; citations gain a second source type; the edition's shape
  doesn't change.
- **Email the edition** to the reader's own address.
- **Private RSS feed of editions** for reader apps.
- **Weekend edition**: one Saturday edition surfacing the week's long-form
  pieces worth a slow read — the most Week-like artefact of all.
- **Public release**: per-user sources and editions, cost controls, and
  the waitlist finally gets something to graduate into.

## Open questions

1. How much of the current feed/reader survives the demotion? Proposed:
   the archive list and the original page stay (citations point at the
   latter); the clean reader stays for archive browsing; read state and
   its routes go. Confirm at build time.
2. Should the editor decide how many leads an edition has (within bounds),
   or is the count fixed? Proposed: editor's judgement, bounded 2–5 — a
   thin news day shouldn't be padded to a quota.
