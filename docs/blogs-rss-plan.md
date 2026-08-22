# Plan: adding blogs via RSS

## What we're building

siftbox currently only receives newsletters, by email. This adds blogs.

The app will check a list of blog feeds on a schedule. New posts get stored
like newsletters do: they appear in the archive, and they go into the daily
edition alongside the newsletters.

The reasoning behind the decisions below is in `docs/blogs-rss.md`. This
document is just the work.

## What's already decided

- **Two new tables, `blogs` and `blog_posts`.** The existing `newsletters`
  table is not touched. Nothing already in the database gets migrated.
- **Aggregator feeds are out of scope** — Hacker News, Reddit, lobste.rs.
  Only real blogs. Their items contain no text, and the AI editor is
  required to write a line about every source it's shown.
- **Use the `rss` gem** to read feeds. Tested against eight real feeds.
- **A shared `sources` table with the silencing work.** See "Working
  alongside the silencing branch" below.

Four milestones. Each one is a branch and a deploy of its own.

## Ground rules for all of them

- Write the test first. That's `.claude/rules/testing.md` and it isn't
  optional here.
- Generate migrations with `bin/rails generate migration`. Don't hand-write
  them, don't edit them after they've merged.
- `bin/ci` has to pass — tests, RuboCop, Brakeman, bundle-audit.
- Style-only changes go in a separate commit from behaviour changes.

---

## Milestone 0 — measure the real feeds

**Why:** the numbers behind the decisions above came from ten feeds I
picked, measured once. They're not your feeds. This is cheap and it's the
last chance to find out something's wrong before there's a database table.

**Build:** a rake task, `feeds:measure`, development only. Give it a list
of feed URLs. It fetches each one, and for every post prints how much text
it actually contains after the app's existing text extraction runs over it.

It stores nothing. No table, no model, no route.

**Done when:** it's been run against your real feed list on a few different
days, and you know two things — roughly how much a day's worth of posts
adds up to, and whether any feed you actually want behaves like an
aggregator.

---

## Milestone 1 — fetch and store posts

Blogs get added, polled, and stored. Posts show up in the archive. They do
**not** go into editions yet.

### Database

Two new tables. Neither touches anything that exists.

**`blogs`** — the subscription and its polling state:

| Column | What it's for |
|---|---|
| `title`, `site_url` | Display |
| `feed_url` | Where to fetch, unique |
| `polled_at` | Last check |
| `etag`, `last_modified_header` | So a poll can ask "changed since last time?" and usually get told no |
| `failing_since` | Set when fetches start failing, cleared when they work again |

`last_modified_header` stores the HTTP header as text rather than as a
timestamp, because servers compare it as text. Reformatting it means you
get a full response every time instead of "not changed".

**`blog_posts`** — one row per post: `blog_id`, `guid`, `url`, `title`,
`body_html`, `snippet`, `lead_image_url`, `published_at`, `received_at`.
The columns deliberately mirror `newsletters`, because the code that
cleans up HTML and extracts text already works on any of them.

### Reading feeds

- **`Blog::Feed`** wraps the `rss` gem and hands back a normalised post,
  regardless of whether the feed is RSS or Atom. The two formats name their
  fields differently — that's about fifteen lines of translation.
- **`Blog::Poll`** does one visit to one feed: fetch, parse, store what's
  new. Running it twice must store nothing the second time.
- **`Blog::PollJob`** runs it in the background.

### Fetching safely

The app already has a careful HTTP fetcher, used for downloading images out
of newsletters. It caps redirects, caps how many bytes it'll read, caps how
long it'll spend, and — importantly — refuses to connect to internal
network addresses. That last part matters: a blog can redirect us to an
internal address, and we'd be making that request from inside our own
network.

That fetcher gets split so feeds can use it too. Three specifics:

- **Feeds need a bigger size limit than images.** The image limit is 5MB.
  Dan Luu's feed is 11.2MB, because it contains his entire archive. Reusing
  the image limit would silently reject a legitimate blog.
- **Read the bytes as UTF-8 explicitly.** Every feed I tested failed
  outright without this. The app already handles the same problem for
  email, in `Newsletter::InboundMessage`.
- **Send the stored `etag` and `last_modified_header` back** on each poll,
  so an unchanged feed costs almost nothing.

### Not storing the same post twice

Use the feed's own id for the post (`guid` in RSS, `id` in Atom). If
there isn't one, fall back to the post's link; if there's no link either,
a hash of the title and date. Scoped per blog, since two blogs can use the
same id.

If a post changes after we've stored it, we ignore the change. The edition
links a claim to what we read; swapping the text out afterwards breaks
that.

### The first poll of a new blog

A feed usually contains the blog's back catalogue, not just what's new. The
eight feeds I measured hold 273 posts between them. If the first poll
treated all of those as "just arrived", they'd all land in one edition —
which would be far too big to send to the model at all.

So: store everything for the archive, but only let recent posts count as
new. This needs to be one clearly-named method with the reasoning written
above it, not a `.limit` tucked into a query.

### Images

Newsletters have their images downloaded and re-served by the app, so the
archive keeps working after the sender's server forgets them. Posts should
work the same way, and the existing code needs almost no change to do it.

**One thing that must not change:** the URLs the app serves images at are
written into the stored HTML when a newsletter arrives. Every stored
newsletter body literally contains `/newsletters/5/images/...` as text. So
posts get their own separate image URLs, and the newsletter ones stay
exactly as they are. Changing them means rewriting every stored newsletter.

### The archive

The archive page has to show newsletters and posts together, which means
combining two queries. It already loads everything into memory to group it
by day, so this is straightforward.

**The one tricky bit is sort order.** Every list in this app sorts by
arrival time and breaks ties using the database id, because email
timestamps only go down to the second and a batch of newsletters can share
one. That trick stops working across two tables — newsletter 5 and post 5
aren't comparable. The sort needs a third component so the order is stable.
Get this wrong and rows shuffle between page loads.

**A post's row says it's a post.** Each archive row carries a small line of
fixed-width text above the headline — the row number, who sent it, and the
time. A post gets one more field on that line: `Simon Willison / Blog`. The
line already draws slashes between its fields, so this is a third field
rather than a badge added on top.

Only posts are marked, not newsletters. Newsletters are the common case —
twenty a day against three — so marking the rarer thing keeps the archive
quieter.

**"View original" on a post is an external link** to the blog. Newsletters
show the original email in a sandboxed frame; a post's real original is the
blog itself. That difference is what the marker is for: you can see where a
row goes before you click it.

The marker is drawn in the app's blue, the same colour as the row number.
If it reads loud once there's a real archive behind it, dropping it to the
grey the rest of that line uses is a one-word change.

### Scheduling

Add an hourly poll to `config/recurring.yml`, production only. Hourly is
plenty — the edition is daily, so polling frequency only affects how fresh
a post is when the edition is written.

**This is a deploy step.** The scheduled task doesn't install itself; the
schedule only exists after a deploy that includes it. `docs/deploying.md`
section 9 explains this for the existing edition job — add the same for
polling, including the command to confirm it registered.

### Done when

Feeds added by hand get polled on schedule. Posts appear in the archive
mixed in with newsletters, in a stable order. Clicking one goes to the
blog. Images are stored locally. Polling an unchanged feed a second time
stores nothing and ideally fetches nothing.

---

## Milestone 2 — put posts into editions

**Database:** one migration. The `edition_citations` table — which records
which sources each story in an edition was written from — gains a
`blog_post_id` column, alongside its existing `newsletter_id`. Exactly one
of the two is set per row.

**Code**, and this is the bulk of the milestone, roughly eighty lines
across six files:

- The query that decides what an edition covers now reads both tables, with
  the same stable sort order as the archive.
- The prompt gets told about posts as well as newsletters, and the response
  format gains a list of post ids beside the newsletter ids. They stay
  separate deliberately — attribution differs, and "the newsletter reports"
  is wrong over a blog.
- The check that every source got written about now runs over both lists.
- The prompt's version number goes up. Editions are immutable and record
  which prompt wrote them, so this is how a change gets tracked.

**Two additions on top:**

- **A minimum text length.** A post below it is stored for the archive but
  never sent to the editor. Real blogs still publish the occasional stub —
  9 of the 273 posts I measured were under 400 characters, mostly Martin
  Fowler publishing an essay in linked fragments. When this holds something
  back it should say so somewhere, not drop it quietly.

  **Where it says so:** a line in the job log naming the post, which is where
  this app says everything else it decided not to do. Nothing reaches the
  reader. The Sources page (Milestone 3) is the place for that, and it can
  read the same rule off `Blog::Post#enough_to_write_from?`.
- **A note when a feed only gives a summary.** Some blogs publish the first
  two lines and a "read more" link. Without a marker, the editor reads that
  as a paywalled article and reports the blog as paywalled, which is false.
  Worth knowing: there's no reliable way to detect this automatically — Dan
  Luu's full articles arrive in the field usually used for summaries, and
  Simon Willison's short posts are short on purpose. So it's a guess and
  should be written as one.

  **What was built instead, and why.** No per-post marker. The plan asked for
  a line appended to short bodies, the way `Newsletter::Prose::OMISSION`
  names this app's own cut — but that marker is honest because the app knows
  it cut the text, and a "this may be an excerpt" line would be the app
  guessing about somebody else's publishing. Since length says nothing (see
  the measurements above), every such line would be a guess printed as a
  fact, on the majority of posts wrongly. What shipped is a standing sentence
  in the instructions: a feed carrying the opening of a post and a link to
  read on is publishing that way rather than charging for the rest, so never
  call a blog paywalled on the strength of a short post. That fixes the false
  paywall. It does not give the reader a "go and read the rest of this" nudge
  on a genuinely summary-only feed, which is the half that was dropped.

**Not doing:** limiting posts per blog, or relaxing the rule that every
source gets written about. At 3 posts a day neither is needed.

**Done when:** an edition regenerated over a window containing posts cites
every source, names blogs correctly, and puts essays on the reading list.
That's a human judgement call, read using the existing
`lib/edition_transcript.rb`.

---

## Milestone 3 — a page to add and remove blogs

Until this exists, blogs are added by hand in a console. Fine for one
reader, but not the finished thing.

- A form to add a feed and a way to remove one, on the Subscriptions page.
- **Refuse aggregator feeds here**, when the feed is added. Sample it, and
  if its posts have no text, decline with a reason: "this looks like a link
  aggregator; siftbox reads blogs". Refusing while the reader is standing
  there is much better than silently ignoring the feed later.
- Optionally: let someone paste a blog's homepage and find the feed URL
  from it.

This could swap places with Milestone 2 — it's lower risk and makes
Milestone 1 usable by someone without console access.

**What shipped.** All three, including the homepage lookup — readers know
their blogs by their home pages and most sites never show a feed address, so
it turned out to be the ordinary case rather than a nicety. The section lives
on the Subscriptions page as agreed with the silencing branch, not on a page
of its own. The aggregator rule is a majority: a feed fewer than half of
whose items carry `Blog::Post::EDITORIAL_MINIMUM` characters of prose is
refused. The measurements are miles either side of that line — aggregators
median eight characters, 9 of 273 in-scope items under four hundred — so it
separates them without a judgement call.

Removing a blog destroys it, along with its posts and the citations in
published editions naming them. Muting, which keeps the archive intact, is
the silencing branch's.

---

## Working alongside the silencing branch

Someone else is building "mute a source so it stops reaching editions", on
`claude/mute-newsletters-reports-kh0rro`. Agreed between us:

- **One shared `sources` table**, listing sources the reader has made a
  decision about. It stores an email address for a newsletter sender, or a
  reference to the blog row for a blog.
- **They ship it first, with the email half only.** The blog reference gets
  added here in Milestone 1. That way they aren't waiting on this work.
- **They own the Subscriptions page.** The add-a-feed form from Milestone 3
  goes inside the section they build, rather than next to it.
- **A rename lands on their branch first:** `Newsletter::Source` becomes
  `Newsletter::Markup`, because the new `Source` model would otherwise
  clash with it. Nothing here should refer to `Newsletter::Source` in the
  meantime.
- **Both branches edit the same query** — the one that picks what an
  edition covers. They narrow it, this widens it. They've agreed to take
  the rebase if they land second.

---

## Deploy steps

Things that don't happen automatically:

| Milestone | Step |
|---|---|
| 1 | Add `gem "rss"` to the Gemfile. It also pulls in `rexml`, which is currently test-only. Mention both in the commit message. |
| 1 | After deploying, confirm the poll task actually registered — `docs/deploying.md` section 9 has the command. |
| 3 | Nothing. Blogs are added on the Subscriptions page, under Blogs. |
| 2 | One migration, additive. No backup needed; nothing is moved or deleted. |

## The three things most likely to go wrong

1. **The archive sort order.** Combining two tables breaks the existing
   tie-breaking trick. If it's wrong, rows shuffle between page loads and
   the archive's numbering goes with them. Nothing fails loudly.
2. **The first poll of a new blog.** Get the "only recent posts count as
   new" guard wrong and adding a blog dumps its entire back catalogue into
   the next morning's edition. It fails loudly, but it fails on the morning
   after you add a blog.
3. **The HTTP fetcher.** It's the only thing stopping a feed URL reaching
   the internal network, and it's about to get a second caller. Its tests
   move with it, and the redirect path is the one to keep covered.
