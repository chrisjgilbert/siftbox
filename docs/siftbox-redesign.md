# siftbox — redesign spec

Implementation spec for the Claude Design handoff (`design_handoff_siftbox/README.md`).
Written before the work, to be read alongside the diff.

The handoff replaces the whole presentation layer and renames the app. The Rails
architecture underneath it — Action Mailbox ingest, one catch-all mailbox, render-time
`sanitize` with an explicit allowlist, hotlinked images, the sandboxed view-original
iframe — is unchanged and stays as it is.

## 1. Decisions

Taken before starting, in answer to the questions the handoff leaves open.

| Question | Decision |
|---|---|
| Lead images and thumbnails (§7) | **In.** New column, extraction at ingest, backfill task. Without it there is no lead item and no thumbnails, which is most of the new feed. |
| Archive (§4.1, §5.1) | **Deferred**, as the README already says. The filter bar is a flex row and the reader top bar is a flex row; both degrade with the control absent. |
| Search (§4.1) | **Deferred.** Note for whenever it lands: this app is SQLite, so `LIKE` — already case-insensitive for ASCII — not the `ILIKE` the handoff assumes. |
| Landing page and waitlist (§3) | **In**, in full. |
| Root path | Landing page for signed-out visitors; signed-in readers redirect to the feed. |
| Rename depth | Everything: Ruby module, `NEWSBOX_*` environment variables, deploy config, docs. |
| Reader lead image (§5.3) | Promoted above the article **and removed from the rendered body**, so it does not appear twice. |

### Three departures from the handoff

**§3.3, the product shot, is static markup — not the live feed.** The handoff asks for
"an abbreviated live feed" on the landing page. The landing page is unauthenticated, so
that would publish the reader's actual subjects and senders to anyone who loads it. The
row spec, scale and caption bar are built exactly as specified; the five rows are fixed
sample content in the template.

**§5.4's sponsor block is dropped.** There is no reliable way to identify a sponsor
section in arbitrary newsletter HTML — it would need a heuristic per sender. Nothing
renders it, and no CSS is written for it.

**`noindex, nofollow` stops being site-wide.** It currently sits in the layout and covers
every page. The landing page wants indexing, so the layout emits it unless a template
opts out:

```erb
<% unless content_for?(:indexable) %>
  <meta name="robots" content="noindex, nofollow">
<% end %>
```

Only the landing page sets `content_for :indexable`. Every app screen keeps the tag.

## 2. Design tokens

Straight from §1 of the handoff, into custom properties in `app/assets/stylesheets/application.css`.
The existing stylesheet is one hand-written file and stays that way.

```
--ink        #0a0a0a   --blue          #1f1fe0
--paper      #ffffff   --hover         #f4f4f7
--body       #4a4a4a   --fallback      #c4c4c4
--mute       #6a6a6a   --landing-paper #f6f6f3
--read       #9a9a9a   --rule          #e2e2e2
```

Two rule weights only: `2px solid var(--ink)` for structural edges, `1px solid var(--rule)`
for rows within a section. No gradients, no shadows, `border-radius: 0` everywhere including
inputs and buttons. The only declared motion is the feed row hover tint and the landing
button hover fill.

Archivo (400/500/600/700/800) and JetBrains Mono (400/500) replace Newsreader and Inter,
from the same Google Fonts origin the CSP already allows — `config/initializers/content_security_policy.rb`
needs no change.

**Mono strings stay sentence case in `config/locales/en.yml` and are uppercased in CSS.**
`text-transform: uppercase` on the mono classes, not `END OF FEED` in the locale file.
Dynamic content — sender names, group labels — needs the CSS rule anyway, so this is the
only way the two agree, and translations stay sane.

Negative tracking scales with size per the handoff's table. Mono tracking runs the other
way, `0.06em`–`0.12em`. Breakpoints stay at 720px and 1024px.

## 3. Logo

`app/views/application/_mark.html.erb`, taking a `size` local, rendering the SVG from §2
with the stroke weight picked from the size compensation table (4 at 64px+, 5 at 20–30px,
6 at 20–22px, 7 at 16px and below). `stroke-width` on the `<svg>`, not per path. The inner
square is always 12×12 at 26,26, solid blue, no stroke.

`public/icon.svg` is the black-tile variant from §2: `#0a0a0a` fill, mark strokes **and
inner square** in `#ffffff` — blue on black fails contrast at icon size, so the accent
drops out, as the handoff specifies.

`public/icon.png` (512×512, same black tile) is generated rather than hand-drawn: the mark
is entirely axis-aligned rectangles, so scaling the 64-unit viewBox by 8 gives exact pixel
boundaries with no anti-aliasing needed. A throwaway script writes it; the script is not
committed, the PNG is.

`app/views/pwa/manifest.json.erb` picks up the new name, description and `theme_color`
(currently `"red"` in both colour fields).

## 4. Rename

`newsbox` → `siftbox` everywhere.

- `module Newsbox` → `module Siftbox` in `config/application.rb`
- `NEWSBOX_TIME_ZONE`, `NEWSBOX_INBOUND_ADDRESS`, `NEWSBOX_HOST`, `NEWSBOX_MAIL_FROM`,
  `NEWSBOX_EMAIL`, `NEWSBOX_PASSWORD` → `SIFTBOX_*`
- `config/deploy.yml`: service, image, the commented variable block, and the storage
  volume `newsbox_storage` → `siftbox_storage`
- `Dockerfile` header comments, `db/seeds.rb`, `README.md`, `CLAUDE.md`, the locale title,
  the manifest, the stylesheet's opening comment

**Deploy step.** The environment variables have to be renamed on the host in the same
release, or the app boots with placeholder values — a feed that tells the reader to
subscribe to `example.com`, reset links pointing at localhost. Nothing is deployed yet
(`config/deploy.yml` still has no host), so today this costs nothing; it will not stay
free.

Renaming the Kamal volume orphans the old one. Again free while nothing is deployed.

## 5. Data model

Two migrations, generated with `bin/rails generate migration`.

### 5.1 `newsletters.lead_image_url`

```ruby
add_column :newsletters, :lead_image_url, :string, default: "", null: false
```

`""` rather than nil, which is what `.claude/rules/database.md` asks of optional string
columns and what every other string column on this table already does. `""` means "no
image in email", which is what the dashed fallback box renders. No index — nothing
queries or sorts on it.

### 5.2 `waitlist_signups`

```ruby
create_table :waitlist_signups do |t|
  t.string :email, null: false
  t.timestamps
end

add_index :waitlist_signups, :email, unique: true
```

Both migrations are additive and reversible. No backup needed before either deploy.

## 6. Lead image capture

**`Newsletter::LeadImage`** — new PORO. Takes body HTML, answers two questions:

- `#url` — the first meaningful `<img src>`, or `""`
- `#remainder` — the same body with that image removed

It works over `Newsletter::Body`'s scrubbed document, so the tracking-pixel scrubber has
already run and a 1×1 beacon can never win. `cid:` and `data:` sources are skipped — by
extraction time the `cid:` references have been rewritten to app paths by
`Newsletter::InlineImages`, so an inline image is a legitimate lead.

The node is found once and memoised, so `#url` and `#remainder` give the same answer in
either call order even though `#remainder` mutates the document.

**Ordering at ingest is load-bearing.** `Newsletter::InboundMessage#store` must extract
*after* `Newsletter::InlineImages#attach`, inside the same transaction — attach rewrites
`body_html`, and extracting first would store a `cid:` URL that no browser can resolve.

**At render**, `NewslettersHelper#newsletter_body` sanitizes `#remainder` rather than
`Newsletter::Body#scrubbed`, so the promoted image does not appear twice. The allowlist
and the fact that `sanitize` returns an already-safe buffer are unchanged — nothing calls
`html_safe`.

**Backfill.** Existing rows have `body_html` but no `lead_image_url`, so without a backfill
the whole feed shows `NO IMAGE IN EMAIL` until new mail arrives. A rake task,
`lead_images:backfill`, walks rows with a blank `lead_image_url` and extracts from stored
HTML. Extraction needs Loofah, so it cannot be plain SQL inside the migration, which is
what `.claude/rules/database.md` asks for.

> **Deploy step:** run `bin/rails lead_images:backfill` once after the migration. It is
> idempotent and safe to re-run.

**Hotlinked**, per §7. Thumbnails are a weaker case for hotlinking than body images —
a dead URL shows on the main screen rather than inside one article — so if a sender's
images start breaking, re-host thumbnails only through Active Storage and leave body
images alone.

## 7. Feed

### 7.1 Numbering

Rows are numbered `01`, `02`, `03`… continuously across the whole feed rather than
restarting per group. The number replaces the burgundy unread dot: blue when unread, grey
when read, and read rows additionally sit at `opacity: 0.66`.

`Feed` threads a running offset across groups — they are disjoint and already in order, so
that is enough — and hands each `Newsletter::Presenter` its number.

### 7.2 Lead item

The newest item in the feed is number 1 and is by definition in the newest group, so
`Newsletter::Presenter#lead?` is `number == 1 && lead_image?`. If it has no image it falls
back to a standard row, exactly as §4.4 says — no full-width placeholder.

### 7.3 Presenter

`Newsletter::Presenter` is at 69 lines and the handoff adds roughly eight display fields.
Rather than push it past the ~100-line mark `.claude/rules/ruby.md` warns about, two
domain objects come out of it:

- **`Newsletter::ReadingTime`** — `#minutes` from body word count, floor 1. Reader only.
- **`Newsletter::IssueNumber`** — parses `#742` or `Issue 612` from a subject, `""` when
  there is none. §5.2 wants the field shown only when parseable.

The presenter keeps formatting: `number`, `lead?`, `lead_image_url`, `kicker`
(`{SENDER} / {DOMAIN}`), `timestamp`, `received_stamp` (`2026.08.05 09:02`), `standfirst`.

**Standfirst** reuses the stored `snippet`. It is already the opening prose of the email,
extracted at ingest through `Newsletter::Body#text` — which is exactly what §5.2 asks for,
and does not cost a second parse of the body on every reader load.

### 7.4 Views

- Header: mark + wordmark left; `EVERYTHING` / `UNREAD [n]` right. No `ARCHIVED`, no
  search icon — both deferred.
- The inbound address moves out of the header into the end-of-feed note, which §4.1 offers
  as an alternative to a settings page and is much the cheaper of the two.
- `_lead.html.erb` (new) and `_row.html.erb` (rebuilt) — the 44/1fr/200/96 grid, the
  200×132 thumbnail, and the dashed `NO IMAGE IN EMAIL` box that keeps the right edge
  aligned when there is no image.
- Mobile per §6: the number, sender and time collapse into one mono line; the thumbnail
  drops to 92×68 and its fallback copy to `NO IMAGE`; snippets are dropped.

## 8. Reader

Top bar, masthead, data strip, lead image, body, previous/next — all per §5, minus the
`ARCHIVE` action.

The data strip carries `RECEIVED …` always, `ISSUE …` only when parseable, and `… MIN`
always. Body typography changes shape in two ways worth calling out: `ul` bullets become
zero-padded mono counters matching the feed index (the em-dash bullets are gone), and
`a` moves to blue with a 3px underline offset.

`img` inside the body keeps its column-width treatment; only the promoted lead image is
full-bleed at 1128px.

View original (§5.6) is untouched — same route, same sandbox, same per-response CSP.

## 9. Landing page and waitlist

### 9.1 Routing

```ruby
resource :waitlist_signup, only: [:new, :create]
root "waitlist_signups#new"
```

The landing page *is* the new-signup form, which keeps the route resourceful without
inventing a `pages` controller. `#new` redirects a signed-in reader to the feed, so opening
the app still lands on the feed.

### 9.2 `WaitlistSignup`

An Active Record model. Email normalised to lowercase and stripped in a callback —
normalisation is what `.claude/rules/models.md` allows callbacks for. Format validated,
nothing sent: the copy promises exactly one message, so a confirmation email would break
the promise on day one.

`#join` is the domain verb.

- **A duplicate is a success.** The unique index raises `ActiveRecord::RecordNotUnique`,
  which `#join` rescues and reports as success. Telling a visitor an address is already on
  the list answers a question about someone else's address.
- **A filled honeypot is also a success**, and writes nothing. `website` is an
  `attr_accessor`, not a column. Returning a 422 would tell a bot which field caught it.

### 9.3 Security

This is the only public write path in the app.

- `allow_unauthenticated_access only: [:new, :create]` — nothing else opens up.
- CSRF verification stays on. It is browser-facing.
- Strong parameters, `:email` and `:website` only.
- Honeypot rather than a captcha, per §3.8.
- `rate_limit to: 5, within: 1.minute, only: :create`.
- `:email` is already in `config/initializers/filter_parameter_logging.rb`, so submitted
  addresses are filtered out of the logs with no change.

> **Open point on rate limiting.** `rate_limit` reads `Rails.cache`, and the test
> environment is `:null_store` — so the limit is a silent no-op under test and cannot be
> covered as things stand. Switching test to `:memory_store` makes it coverable and risks
> nothing else (nothing in this app caches). Proposed, and called out here rather than
> slipped into the diff.

### 9.4 Success state

Rendered in place, both form instances switching together, per §3.6.

`_waitlist.html.erb` renders the form; `_joined.html.erb` renders the success state. Which
one appears is passed down as a local naming the partial, so neither template carries a
conditional and neither needs a state flag on the model:

- `new.html.erb` → landing with `waitlist: "waitlist_signups/waitlist"`
- `create.html.erb` → landing with `waitlist: "waitlist_signups/joined"`
- `create.turbo_stream.erb` → replaces both instances with the joined partial

Both instances take an `inverted` local for the dark closing band, where the form flips to
white-on-black and the success copy drops its second sentence.

The Turbo Stream is the real path. The HTML templates are the no-JS fallback and are what
request specs assert against.

### 9.5 Page

Per §3: dotted `#f6f6f3` lattice on a wrapper div rather than a second layout, 1240px
container, 2px-ruled nav, 88px hero, the static product shot from §1's departure note, the
two-point grid, the full-bleed dark closing band, and the mono footer.

## 10. Tests

`.claude/rules/testing.md`: test first, no `let`, no `before`, four phases, `build_stubbed`
where persistence is not needed.

New specs:

- `spec/models/newsletter/lead_image_spec.rb` — first image wins; tracking pixels never
  win; `cid:` and `data:` skipped; `""` when there are no images; `#remainder` drops the
  lead and only the lead
- `spec/models/newsletter/reading_time_spec.rb` — word count to minutes, floor of 1
- `spec/models/newsletter/issue_number_spec.rb` — `#742`, `Issue 612`, and no match
- `spec/models/waitlist_signup_spec.rb` — joins, rejects a malformed address, duplicate
  reports success, honeypot writes nothing
- `spec/requests/waitlist_signups_spec.rb` — landing renders signed out, signed-in reader
  redirects to the feed, create writes, duplicate still succeeds, honeypot writes nothing,
  Turbo Stream replaces both instances

Updated:

- `spec/models/feed_spec.rb` — continuous numbering across groups
- `spec/models/newsletter/presenter_spec.rb` — number, `lead?`, kicker, data strip
- `spec/requests/newsletters_spec.rb` — filter copy, the `row__domain` assertion, and a new
  one: the promoted lead image renders once, not twice
- `spec/factories.rb` — `lead_image_url`, `waitlist_signup`

`lib/tasks/sample_data.rake` gains lead image URLs so the development feed shows the design
rather than a column of fallback boxes.

## 11. Commits

In order, each green on `bin/ci`:

1. Rename newsbox to siftbox
2. Capture the lead image from each newsletter — migration, `Newsletter::LeadImage`,
   ingest wiring, backfill task. No UI.
3. Design tokens, fonts, logo and icons — plus sign-in and password screens, which would
   otherwise read as a different app
4. Rebuild the feed
5. Rebuild the reader
6. Landing page and waitlist
7. Documentation — README and CLAUDE.md

## 12. Deploy steps

Nothing here drops data, and both migrations reverse cleanly, so no backup is needed
before staging or production.

1. Rename the `NEWSBOX_*` environment variables to `SIFTBOX_*` **in the same release** as
   the code, or the app boots on placeholder values.
2. Run `bin/rails lead_images:backfill` once after migrating. Idempotent.
3. The Kamal storage volume is renamed. Free today because nothing is deployed; it will
   need a data move once something is.
