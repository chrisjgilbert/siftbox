# PRD: Editions — a twice-daily briefing

Draft for discussion. Decisions marked **Proposed** are recommendations with
reasoning; decisions marked **Open** genuinely need the reader's call.
Nothing here is implemented yet.

## The idea

siftbox today is a newsfeed: every newsletter arrives as a row, and the reader
triages and reads each one individually. The model to move to is The Week:

> a news digest that does almost no original reporting. Editors read a large
> volume of newspapers, magazines and websites, then condense that coverage
> into short summaries, deliberately drawing on outlets from across the
> spectrum.

Here, the newsletters (and later, blogs via RSS) are the original reporting.
An AI editor reads everything that arrived since the last edition and writes a
short briefing. The briefing — not the feed — becomes the thing the reader
opens.

Two editions a day:

- **Morning edition**, ~07:00 Europe/London — covers the overnight window,
  which is when US newsletters land.
- **Afternoon edition**, ~15:00 Europe/London — covers the day so far,
  catching US morning releases.

## Jobs to be done

1. **Catch me up.** When I open the app, tell me what mattered across all my
   newsletters since I last looked, without me triaging each email. This is
   the core job; today it takes a scroll through the feed and N opens.
2. **Collapse duplicate coverage.** When four newsletters cover the same
   story, I want one synthesis that notes the differing angles — read it
   once, not four times. This is where an edition beats per-email TL;DRs.
3. **Route me to the good stuff.** The briefing is a router, not a
   replacement. When something deserves a full read, the edition should say
   so and link me straight into the reader.
4. **Absorb my absence.** After a weekend away I want one catch-up read, not
   scroll guilt over thirty unread rows.
5. **Keep the archive honest.** The feed and reader stay as the source of
   record. Every claim in an edition traces to an original I can open.

## Product decisions

### Edition shape — **Proposed: hybrid**

Two sections per edition:

1. **Lead stories** (roughly 2–4): themes the editor found across sources,
   each a short synthesised paragraph with attribution — "Money Stuff and
   The Diff both read the Figma S-1; Levine focuses on…". This is the
   Week-style editorial value.
2. **In brief**: one line per newsletter not already cited in a lead story,
   in received order, each linking to the reader.

Why not story-first everywhere: pure cross-source clustering is the hardest
prompt to get right, and on quiet days most newsletters share no story — the
structure needs a home for singletons anyway. Why not source-first TL;DRs
only: that is a compressed feed, not an edition, and gives up job 2.

### Completeness — **Proposed: cover everything**

Every newsletter in the edition's window appears somewhere — cited in a lead
story or listed in brief. This is a hard validation on the generated output,
not a hope about the prompt. The briefing can only replace feed triage if
missing something is impossible.

### Entrypoint — **Proposed: the edition is home**

Signed-in root shows the latest edition. The feed remains intact one click
away as the archive. Rationale: if the edition is good, it is what the reader
wants first; if it is not good, side-by-side placement would just let it rot
politely. Making it home forces the quality question early — right for a
one-person prototype.

### Edition windows — **Proposed: high-water mark, not fixed windows**

An edition covers newsletters received after the previous edition's cutoff,
up to the moment it is composed. No fixed 15:00→07:00 ranges: with fixed
windows, a failed run or a late-arriving email falls into a gap and is never
covered. With a watermark, a newsletter is covered by exactly one edition,
whichever runs next. `received_at` (already indexed) is the clock.

### Empty windows — **Proposed: skip silently**

No newsletters since the last cutoff → no edition. A "nothing arrived"
edition is noise, and the watermark means the next real edition still covers
everything. The home page shows the most recent edition regardless of age,
with its timestamp doing the honesty work.

### Read state — **Open**

Options:

- **a) Decoupled (lean this way).** Reading an edition does not touch
  `read_at`. Clicking through to a newsletter marks it read as today. Unread
  in the feed keeps meaning "original not opened", and the feed's unread
  filter becomes "what the edition summarised but I never opened" — arguably
  more useful, arguably nagging.
- **b) Edition read = all covered newsletters read.** The edition is the
  read; the feed's unread count drops to zero twice a day. Cleaner if the
  edition truly replaces triage, but destroys "which originals did I
  actually read".

Depends on how the reader wants unread to feel after living with editions
for a week. Ship (a), revisit.

### Delivery — **Proposed: web only for v1**

Editions live in the app. Email delivery of the edition (the digest arriving
where the newsletters would have) and a private RSS feed of editions are both
natural later steps — noted under Future, not v1.

## Requirements

### Functional

- Compose an edition at ~07:00 and ~15:00 Europe/London on a schedule
  (Solid Queue recurring task; DST handled by scheduling in the zone, not
  UTC). Per `.claude/rules/review.md`: a scheduled task is a deploy step and
  must be called out in the deploy docs.
- An edition records: its slot (morning/afternoon), when it was published,
  the window it covered, its stories and briefs, and which newsletters each
  cites.
- Every newsletter in the window is cited at least once (validated
  mechanically against the model output; regenerate on failure).
- Edition page renders lead stories with attribution links into the reader,
  then the in-brief list. Design follows `docs/siftbox-redesign.md` — the
  masthead ("Morning edition · No. 41") is a natural JetBrains Mono job.
- Editions are browsable as an archive: `resources :editions, only:
  [:index, :show]`.
- Signed-in root serves the latest edition; the feed moves to its existing
  `/newsletters` path with navigation between the two.
- A failed run retries; a morning edition composed late is still the morning
  edition (labelled by slot, not by wall clock).
- One edition per slot per day, enforced with a unique index.

### AI editor

- Input: per-newsletter plain text extracted from `body_html` (the reader
  pipeline already understands these bodies; strip to text, cap per-source
  length), plus sender, subject, received time.
- Output: structured JSON — lead stories (headline, summary, cited
  newsletter ids) and briefs (newsletter id, one-liner) — never free-form
  HTML. Rendered through normal ERB escaping; the model's words get no
  `html_safe` path, ever (`.claude/rules/security.md`).
- Store alongside the edition: model name, prompt version, token counts,
  and the raw response — enough to debug a bad edition and to regenerate
  after a prompt change without re-fetching anything.
- Editorial constraints in the prompt: summarise only what the sources say;
  attribute claims to their newsletter; note disagreement between sources
  rather than resolving it; no outside knowledge or invented links.
- Cost envelope: ~10–20 newsletters × a few thousand tokens, twice daily —
  tens of cents a day on a mid-tier model. Not a constraint at one reader;
  worth a line item in any public-release thinking.

### Non-functional

- Composition is a background job; nothing in the request path calls the
  model. A reader mid-morning sees the last published edition, never a
  spinner.
- The API key lives in credentials. Failures alert via logs for now (it is
  one reader who will notice a missing edition anyway).
- Tests stub the model client with a fake (`.claude/rules/testing.md`:
  prefer a fake object over stubbing HTTP; WebMock blocks the rest).

## Data model sketch

For discussion, not a migration:

- `editions` — `slot` (morning/afternoon), `published_at`,
  `window_started_at`, `window_ended_at`, `model`, `prompt_version`,
  `raw_response`. Unique on `(published_on-derived date, slot)`.
- `edition_stories` — `edition_id`, `position`, `headline`, `body` (plain
  text/markdown). A brief is a story with one citation and no headline, or a
  separate `edition_briefs` table — leaning separate tables, since the two
  sections render and validate differently.
- `edition_citations` — `story/brief → newsletter_id`. This is the joint
  that later admits RSS items: when blogs arrive, citations point at a
  second source type. Not building polymorphism now (`.claude/rules/ruby.md`:
  no code for functionality that doesn't exist) — but the citation table is
  the seam, and it's cheap to keep it a real table rather than embedding
  newsletter ids in story text.
- Domain objects per `.claude/rules/models.md`: `Edition`,
  `Edition::Editor` (a noun — it composes an edition from a window of
  newsletters, `#compose`), `Edition::PublishJob`. No `*Service`.

## Edge cases

- **Digest-of-digests newsletters** (TLDR, Benedict's Newsletter): already
  summaries of many links. Summarising them flattens badly. The prompt
  should treat link-list newsletters as a menu — pull the 2–3 most notable
  items — rather than summarising the summary. May eventually want a
  per-sender hint.
- **Huge bodies**: bodies run to hundreds of KB of HTML. Text extraction
  plus a per-source cap keeps the prompt bounded; if a window is still too
  large (catch-up after downtime), chunk by source and compose in two
  passes.
- **Same story, five sources**: the core value case — must cluster, not
  repeat five times.
- **Non-newsletter mail** to the ingest address (receipts, spam): today it
  lands in the feed; in an edition it would be summarised deadpan. Existing
  problem made louder; out of scope here but worth a note.
- **A newsletter arriving mid-composition**: the watermark is the moment
  composition starts; anything later belongs to the next edition.
- **Model hallucination**: structured output + citation validation + the
  original one click away. The edition never needs to be trusted further
  than its links.
- **Prompt iteration**: regenerating a published edition overwrites history.
  Proposed: editions are immutable once published; prompt changes apply
  from the next edition. A dev-only regenerate task is fine.
- **DST**: schedule in Europe/London so 07:00 means 07:00 all year.

## Assumptions

- One reader, one global timeline — editions, like `Feed`, are unscoped
  behind the authentication gate. Multi-user means per-user editions, N×
  model cost, and per-user schedules; acknowledged and deferred, same as
  the README's note on multiple users.
- English-language sources.
- The Anthropic API (or equivalent) is reachable from production and its
  latency (tens of seconds for a big window) is fine in a background job.
- Twice-daily cadence is a starting guess. The mechanism (slots +
  watermark) doesn't care if it becomes once daily or thrice.

## Non-goals for v1

- Blogs / RSS ingestion (the citation seam is left ready; see Future).
- Email or RSS delivery of editions.
- Personalisation, feedback ("more like this"), topic weighting.
- Search, audio, multi-user, public sign-up.
- Any change to ingestion or the reader.

## Success measures

Honest ones, at n=1:

- The reader opens the edition first, and the feed stops being the daily
  entrypoint within a couple of weeks.
- Click-throughs from editions feel right — the editor routes to the pieces
  the reader would have picked anyway.
- Time-to-caught-up drops from "scroll and open each" to one read.
- A month in, no edition has misattributed or invented a claim that the
  citation links exposed.

## Future

- **RSS/blog sources**: a second ingest path writing a sibling of
  `Newsletter`; citations gain a second source type; the editor's input
  gains a source kind. The edition model shouldn't need to change shape.
- **Email the edition** to the reader's own address — the digest arrives
  where the newsletters would have.
- **Private RSS feed of editions** for reader apps.
- **Weekend edition**: one Saturday edition covering the week's long-form
  pieces worth a slow read — the most Week-like artefact of all.
- **Public release**: per-user sources and editions, cost controls, and the
  waitlist finally gets something to graduate into.

## Open questions

1. Read-state coupling (see above) — decoupled or edition-marks-read?
2. Should the in-brief line for a link-list newsletter be its top items or
   a one-line gist? (Affects prompt, not schema.)
3. Morning at 07:00 — before or after the US west coast evening sends
   (~01:00–03:00 UK)? 07:00 catches them; confirm that matches the actual
   senders' rhythm once real data is in.
4. Does the edition number continue the feed's issue numbering or start its
   own ("No. 1")? Cosmetic, but mastheads are the product's personality.
