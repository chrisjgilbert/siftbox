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

- **That the copy comes back in the shape version 3 asks for.** Paragraph
  breaks and the `- ` that opens a list item are instructions, not schema:
  the structured-output validator can enforce neither. `Edition::Story::Body`
  degrades to one paragraph when neither appears, which is exactly what
  version 2 produced, so nothing breaks if the model ignores the request —
  but whether leads actually arrive in two or three paragraphs, and whether
  a list is ever the honest shape for one, is judged by reading
  `edition:backtest` output.

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

Smaller things this milestone found and left alone:

- **The chrome rules are still only proven against invented mail.** The review
  found two ways they misfire — a UK postcode pattern that also matches
  "an M2 8GB", and boilerplate that only matched a typewriter apostrophe — and
  both were found by reading, not by the corpus, whose bodies were written to
  the same assumptions as the rules. Both are fixed, but the pair is evidence
  about the method rather than about those two lines: the next such bug is
  found by dumping `Newsletter::Prose` over real stored bodies and reading the
  output, which is Milestone 0's backtest.

## Milestone 3 — what a deploy has still to prove

The window, the numbering, the job, the schedule and the two dev tools are
written and green. What is green is again the plumbing: no edition has been
composed by a scheduler, and none has been composed at all outside a spec.

- **Nothing has run under a real scheduler.** `spec/config/recurring_spec.rb`
  reads `config/recurring.yml` the way `SolidQueue::RecurringTask` does and
  reproduces its two validations rather than calling them — the queue database
  is not part of the test schema, so the class cannot be instantiated in test.
  Whether the scheduler boots inside Puma with this entry, picks the task up
  and runs it at 07:00 is a fact about the deploy, and the first evidence
  either way is an edition, or no edition, on the first morning after it.
  `docs/deploying.md` step 9 is what makes that a step somebody takes rather
  than a thing that was supposed to happen by itself.

- **No run has crossed a DST boundary.** The cron carries the zone
  (`every day at 7am Europe/London`) and Fugit resolves it to 07:00 +0000 in
  January and 07:00 +0100 in July, which is the whole of the evidence. Nothing
  has travelled to 25 October. The window compares absolute instants either
  way, so the exposure is the firing time and `published_on`, not the
  selection.

- **Nothing watches a failed job.** `Edition::Draft::Unavailable` past four
  attempts, `ActiveRecord::RecordInvalid` from a section word the model
  invented, and any unforeseen `Edition::Draft::Error` land in
  `solid_queue_failed_executions`. There is no `mission_control-jobs` in the
  `Gemfile` and no alerting, so "loud" means a line in a container log nobody
  is subscribed to, and the monitoring plan is one reader noticing a missing
  edition. Worth deciding before the first outage rather than after it.

- **The pre-feature archive belongs to no edition.** `FIRST_WINDOW = 1.day`,
  so No. 1 reaches back twenty-four hours and the weeks of mail stored before
  editions existed are covered by nothing, ever. Deliberate — an unbounded
  first window is one prompt several times over the token ceiling — and
  written down in the deploy doc so the operator reads it before the first
  morning. If that is not acceptable, the answer is a backfill task composing
  historic windows in chunks, and this doc line changes with it.

- **`edition:backtest` can no longer read more than the last edition left
  over.** It asks `Edition::Window` now, so the `DAYS` argument is gone with
  the hand-picked range it built. On a development database whose newest mail
  is older than a day — any production dump read the following afternoon —
  the rehearsal is empty and the tools left are `edition:corpus` and
  `edition:regenerate`. If iterating over a chosen span turns out to be
  wanted, it should be an explicit start on `Edition::Window` rather than a
  second window definition rebuilt inside the task.

- **`edition:regenerate` destroys the edition it rewrites, and the guard is
  the environment rather than the data.** The row goes, and its stored
  `raw_response` — the only copy of the old answer — goes with it; there is no
  undo and nothing writes it out first. `Rails.env.development?` is the whole
  of the protection, and a development database restored from a production
  dump is production data. If comparing two answers side by side becomes part
  of iterating, the task needs to dump the old response somewhere before it
  destroys the row.

- **The corpus still cannot exercise the window.** `edition:corpus` picks its
  newsletters by name and builds its own unsaved edition, which is the point
  of it, so the watermark, the two-clause selection, the empty-window skip and
  the numbering are exercised by specs and by `edition:backtest` only. In
  particular **nothing rehearses the released clause**: the corpus holds a
  confirmation and never releases it, so the one path three review agents
  called easy to get wrong is covered by specs and by whatever real mail
  happens to be released into a backtest's window.

- **Whether a regeneration converges is the same unknown as before.** The
  round trip — destroy, re-compose, replace — is specced against
  `FakeAnthropic`. Whether a second pass over the same window with a changed
  prompt passes the completeness check on the first attempt, and what a round
  of iteration costs at a full-price request per attempt, is answered by
  running it.

- **The rake tasks are not in the suite.** `lib/tasks/editions.rake` is
  outside the autoload path, so `Backtest` and `Regeneration` cannot be
  reached from a spec; what could be specced was put in
  `lib/edition_regeneration.rb`, which is. Left unspecced: the printing, the
  `Rails.env.development?` guards, and the date argument. All of it was run by
  hand against the test database with a fake client — empty window, real
  two-clause window, a date already published, a date with no edition, and a
  full regeneration — and none of it is guarded against regression.

- **`Edition.newest_first`'s comment is stale.** "A run that fails at 07:00
  and retries the next morning still publishes the earlier day's edition"
  describes something `Edition::CompositionJob` cannot produce: retries stop
  after forty-five minutes and a late run dates itself today. The conclusion
  still holds for a manual backfill; the example is wrong.

- **The PRD and the deploy doc disagree about where the API key lives.** The
  PRD says credentials; `Edition::Draft#client` reads
  `ENV.fetch("ANTHROPIC_API_KEY")` and the deploy doc now wires it as a Kamal
  secret to match the code. One of the two should give.

## Milestone 4 — what the pages leave open

The edition page, the archive and root are built and green. The five findings
this section used to hold are all closed: the citations preload
(`Edition.for_reading`, held by a query-count spec), the column list on the
citation association (`Newsletter::CITATION_COLUMNS` — the newsletters query
reads four columns and no `body_html`), the section readers wrapped by
`Edition::Presenter` rather than duplicated, `Section#name` as the
view-facing section word, and the number/date ordering, which the archive now
states in its own caption. What is left:

- **Nothing has been looked at in a browser.** There is none on the machine
  the work was done on (`chromium`, `chrome`, `firefox` all absent), so the
  system specs run under rack_test and prove words, links and order — never
  appearance. The type scale, the two ruled bands of the masthead, the
  archive row's grid and both 720px breakpoints have been read and not seen,
  and no screenshot exists. First person with a browser should open an
  edition and the archive at both widths.

- **Root's empty morning is a decision, not a requirement.** The PRD says
  root serves the latest edition and says nothing about the day before there
  is one. A signed-in reader now gets the editions archive, whose one line
  says the first edition is written at 07:00. The alternatives were an empty
  edition page (a masthead over nothing, and no number to put on it) and the
  originals feed (the surface the edition is meant to demote). Cheap to
  overrule; it is one method, `WaitlistSignupsController#reader_home_url`.

- **The archive is unpaginated**, knowingly against
  `.claude/rules/database.md`, with the reason on `Edition::Archive`: one row
  a day, and an archive that hides its oldest entries is the one thing an
  archive must not do. It reads three columns a row. Revisit when it is long
  enough to notice.

- **`Edition#reading_list?` has no caller** outside its own two specs. The
  presenter drops any empty section uniformly rather than special-casing the
  reading list. Left in place; it is Milestone 1's code and a plausible
  caller may yet appear.

- **`Edition.for_reading` still selects `editions.*`**, so the show page
  reads one edition's `raw_response` — the model's whole answer — to render a
  masthead. One row, so it was left alone rather than given the
  `ARCHIVE_COLUMNS` treatment: a column list here is a `MissingAttributeError`
  waiting for whatever Milestone 5 adds to the page.

- **`EditionTranscript` does not use the section readers**, contrary to the
  reason recorded on `Edition::Presenter` for wrapping rather than moving
  them: it partitions `edition.stories` itself against its own `HEADINGS`.
  The reason still holds on `Edition::Editor`'s specs and the corpus, which
  do call them. Two places now know the order the sections read in.

- **The archive row says nothing about what an edition held** — no story
  count, no senders. It would cost a join or a counter cache, and the archive
  is for finding a day rather than judging one, so it prints the day and the
  number. Reconsider if the reader scrolls it looking for something.

- **`docs/siftbox-redesign.md`'s decision table still says a signed-in reader
  redirects to the feed.** It was written before this feature and describes
  what root did until this milestone. Left as the record of that work; the
  PRD supersedes it.

## Milestone 5 — what the confirmation pen leaves open

The feature is built and green, end to end in code: detection at ingest
(`Newsletter::Confirmation`, asked inside the storing transaction), the
backfill for mail stored before it existed, the Subscriptions page and its
three sections, both resolutions as nested `only: :create` resources, the pen's
own top bar on the original, and the notice on the edition page. Every bullet
of the PRD's "Subscription confirmations" section has code behind it and specs
over it, and the two findings the "For Milestone 2 and 5" section used to hold
are closed with it: the backfill goes through `Newsletter#hold` rather than a
bulk write, and it leaves mail a published edition cites alone — the window an
edition covered is history, and `Edition::Window`'s released clause would
otherwise carry such a newsletter into a second edition.

Two things a browser found that the suite could not. The nav grew a third link
and stopped fitting a 320px screen, scrolling every page sideways rather than
wrapping — fixed here. And the public landing page overflows between roughly
768px and 900px: `.waitlist--inverted` keeps a fixed 620px width at a left
offset that assumes more room than a tablet has, so it is correct at 719px and
at 1280px and broken in the middle. That one is pre-existing, untouched by
Milestones 1–5, and left alone deliberately — the dark closing band is a
deliberate part of the landing design per `docs/siftbox-redesign.md` §9, so the
fix wants whoever owns that page rather than a guess from here.

Neither was catchable by the specs as they stand: Capybara runs under
`rack_test`, which renders no CSS, so no system spec in this repo can see a
layout overflow. A JavaScript driver would be the thing that closes that gap,
and nothing here has one.

What none of that is, is evidence from real mail. What the milestone leaves
open:

- **Nothing has been looked at in a browser**, for the same reason Milestone 4
  could not be: none is installed. The pen's three-column grid, its 720px
  breakpoint and the step-down on the bounced section have been read and not
  seen, and so have the two things this milestone added to the visual system:
  the pen top bar, which wraps rather than hiding an action on a narrow
  screen, and the notice band, which relies on the masthead's rule above it to
  be the second of the two rules it sits between. Both `button_to` forms have
  only ever been posted by rack_test; no real Turbo has driven them.

- **Nothing has been through a real double-opt-in.** No live subscription has
  been confirmed through this app: the chain webhook → hold → pen row →
  sender's confirm button in the sandboxed frame → Done has never run outside
  the suite, and the confirm click is the one link in it the app cannot
  observe even when it does. The deploy's smoke test now ends with it.

- **The phrase set has never met real mail**, and the backfill has never
  walked a real archive. Run `bin/rails confirmations:preview` before
  `confirmations:backfill` on the first deploy — a hold's only undo is a
  release, and releasing three-week-old mail carries it into tomorrow's
  edition. Known gaps a real archive may show: "Almost there", "Action
  required", "One more step" and "Welcome to X" match nothing.

- **The bounced section is capped at twenty rows and says nothing when it
  truncates.** The cap is real — each row downloads and parses a stored raw
  email, and a spam flood is exactly when the section fills — but a reader
  looking for their own eaten confirmation in row twenty-one has no way to
  know it is there. An "and N more" line needs a count query the section does
  not otherwise pay for. Revisit the first time it truncates.

- **Nothing holds the bounce list's file reads.** The query-count spec on
  `/subscriptions` counts SQL, and the blob download `Subscriptions::Bounce`
  does per row is a file read. `with_attached_raw_email` keeps the *queries*
  flat; the reads scale with the section and only the cap bounds them.

- **A held confirmation from a first-time sender is listed twice**, once under
  Awaiting confirmation and once under New senders. Deliberate — the PRD asks
  for first-time senders "flagged or not", and the second section is the net
  for the case where the first one is wrong — but it is the first thing a
  reader will ask about, and it makes `click_link` ambiguous in a system spec.

- **`Newsletter::Age` now includes `ActionView::Helpers::DateHelper`** to say
  "4 minutes ago". A model reaching into ActionView for a phrase; the
  alternative was writing the distance table again, or putting the one thing
  the pen most needs into a helper the presenter cannot reach.
  `Subscriptions::Bounce` then hands it an `ActionMailbox::InboundEmail`'s
  `created_at`, which is not a newsletter's `received_at` — the class is named
  for the narrower of the two things it now measures.

- **`Newsletter.first_from_sender` is only ever called with a date bound.**
  With one it rides `index_newsletters_on_received_at` and the correlated
  subquery rides `index_newsletters_on_sender_email` — both verified with
  `EXPLAIN QUERY PLAN`. Unbounded it scans, the same caveat `Newsletter.content`
  already carries below.

- **The window and the wording cannot drift, but the window itself is a
  guess.** `Subscriptions::NEW_SENDER_WINDOW` is fourteen days because the PRD
  says "the last couple of weeks", and the empty line interpolates the number
  out of the constant. Whether a fortnight is the right amount of memory is
  something only a real archive can say.

- **A resolution posted for mail that is not in the pen is silently a
  redirect.** Both controllers act only `if newsletter.held?`, because the
  state machine raises on the contradictions — dismissing released mail,
  releasing dismissed mail — and a second tab open on the same original is not
  worth a 500. The reader gets the pen and no explanation of why nothing
  happened. The pen does answer it, in that the row is not there; whether that
  is enough is a question for the first time it happens by accident.

- **Nothing in the app behind the gate flashes.** A resolution's only receipt
  is the pen it lands on with the row gone, which is deliberate — the design
  system has no notice component but the notice band, and that one is state
  rather than a message. A reader who opens a held original from a bookmark
  rather than from the pen is therefore sent, on Done, to a page they did not
  come from. Cheap to revisit, and it would want a surface in the redesign
  first.

- **The notice counts every hold, however old.** That is failure path 4
  working as written — it cannot scroll away, and an expired confirm link just
  means subscribing again, which flows through the pen — but it also means one
  confirmation nobody ever resolves keeps the band on the edition page for
  good. The only way to clear it is to resolve the mail.

- **The notice is on the two edition pages and nowhere else.** The PRD asks
  for the edition page; the archive carries it too because root serves the
  archive on a morning before No. 1 exists, which is exactly when a reader is
  subscribing to things. The originals archive and the Subscriptions page
  itself do not, and the masthead's Subscriptions link is what reaches the pen
  from those. It costs one `COUNT` per page load either way: the edition page
  measured five statements before this milestone and six after, whether the
  pen is empty or five deep, on `index_newsletters_on_held_at`.

- **The plural is English only.** `subscriptions.badge.line` has `one` and
  `other`, which is Rails' pluralisation doing the work rather than a
  conditional in a template, but a language with more plural forms would need
  the keys and nothing warns about that today.

## Milestone 6 — what the teardown leaves behind

The reader, its previous/next links, its reading time and read state are gone,
the archive's rows open the original, and the shared masthead finally owns the
`masthead` block name. `bin/ci` is green at 780 examples, down from 853: the
count moved by roughly what was deleted, which is the check that the specs
were covering the removed code rather than passing vacuously over it.

- **`Newsletter::Presenter` survived, against the PRD's wording.** "The
  presenter goes" was written before Milestones 4 and 5 gave it two consumers
  the reader never had: `Subscriptions::Row` and `Edition::Story::Presenter`
  both want a sender line that survives mail with no From header. What is left
  is `#sender` and `#timestamp`; the article body, the promoted image, the
  kicker, the issue number, the reading time and the neighbour wrappers went.
  Deleting the class outright would have copied `#sender` into three places.

- **The landing page's product shot still draws a read row.** `.shot__row--read`
  and its muted number are a mock of the feed in the marketing artwork, and
  the feed it mocks no longer dims anything. Left alone deliberately — it is
  the landing page's own composition, not a stale reference to live code — but
  it is now a picture of a screen that does not exist.

  **Closed.** The shot draws an edition now, and `.shot__row--read` went with
  the feed markup it belonged to.

- **Nothing verified the archive in a browser after the header changed.** The
  system specs run under `rack_test`, which renders no CSS, so what is proven
  is markup and links rather than layout. The archive wears the shared
  masthead now instead of its own two-band header, and the two are not the
  same height.

- **`read_at` is gone for good.** The migration reverses in shape and not in
  content, so a rollback returns every newsletter as unread. `docs/deploying.md`
  carries the backup step; the rollback plan for this release is restore.

- **A whole measure-and-size chain died with the reader and is still in the
  tree.** The review after the teardown found it; it is the largest thing this
  milestone leaves behind, and it is dead code rather than a bug, so nothing
  was removed without a decision. What is orphaned, each verified by grep
  rather than assumed:

  - `Newsletter::ImageDimensions` — no caller outside its own spec.
  - `Newsletter::IssueNumber` — no caller outside its own spec; the presenter
    method it served went with the reader's data strip.
  - `Newsletter::LeadImage#remainder`, `#alt`, `#caption` and their
    figure-detection helpers — only `#url` is called now, by
    `Newsletter#capture_lead_image`.
  - `Newsletter::Body`'s `dimensions:` argument, `#sized`,
    `#apply_stored_sizes`, `#strip_sender_sizes`, `SIZED_ATTRIBUTES`, and
    `TAGS`/`ATTRIBUTES` (which existed for the deleted helper's `sanitize`).
    All three surviving `Newsletter::Body.new` callers pass no dimensions.
  - `lib/tasks/images.rake` (`images:analyze`) and the `image_processing`
    gem behind it. The measured width and height reached a page only through
    `Presenter#reading_body`, which is gone. `Newsletter::Source` does not use
    `Body` at all, and the images controller serves blobs directly with no
    variants, so nothing else needs the analysis.

  Removing it would take a gem, a rake task and step 6's `images:analyze` out
  of `docs/deploying.md`, which is why it is written down rather than done:
  it is a second teardown with its own deploy note, not a tidy-up. The PRD's
  "the image-serving and scrubbing pipeline stays" still holds — that is the
  ingest side, which feeds the original frame and is untouched. What died is
  only the sizing the reader needed to stop images shifting the article.

  **Partly closed.** The sizing is gone: `Newsletter::ImageDimensions`,
  `Newsletter::Body`'s `dimensions:` argument, `#scrubbed`, `#sized`,
  `#apply_stored_sizes`, `#strip_sender_sizes`, `SIZED_ATTRIBUTES`,
  `TAGS`/`ATTRIBUTES`, and `Newsletter::LeadImage#remainder` — each
  re-checked by grep before it went. What is left is the second teardown this
  entry warns about, because it drops a system dependency rather than code:
  `lib/tasks/images.rake`, the `image_processing` gem, the libvips install in
  the `Dockerfile`, in CI and in the session hook, and step 6 of
  `docs/deploying.md`. `Newsletter::IssueNumber` and
  `Newsletter::LeadImage#alt`/`#caption` are still here too; they are dead for
  the same reason but are not sizing, so they were left with it.

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

- **The landing page's product shot still sets each story as one paragraph.**
  `app/views/waitlist_signups/_shot.html.erb` draws fixed locale copy rather
  than the reader's edition, and its stories are two sentences each, so
  nothing in it reads as the wall of text the edition page had. It does mean
  the shot no longer shows every shape the real page draws. Worth revisiting
  if the shot ever grows a full-length lead.

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
  which is self-contained and shares no state with the rest. Milestone 5 has
  since taken the name for something else — `Newsletter::Confirmation` is the
  ingest detector, which reads a subject and a sender and writes nothing — so
  what was rejected here is specifically moving the pen's timestamps, verbs
  and predicates off `Newsletter`.

- **Replacing `dismissed_at`/`released_at` with `resolved_at` plus a
  `resolution` string.** It would make the illegal both-set state
  unrepresentable and delete one validation. Rejected because
  `.claude/rules/database.md` asks for a timestamp behind each boolean
  concept, the saving is one validation and one predicate, and the two
  validations already close the hole.
