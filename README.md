# siftbox

Receives newsletter emails at one dedicated address via Action Mailbox and
Postmark, and presents them as a clean reading feed for a single reader.

Three screens. A public landing page with a waitlist, which is what `/` serves
a signed-out visitor. A feed grouped by the day mail arrived, numbered
continuously so it reads as an index, with a thumbnail pulled from each email.
And a reader that strips the sender's styling and re-renders the newsletter in
the app's own typography. There is an escape hatch — "View original" — that
shows the sender's HTML in a sandboxed iframe.

## Getting started

```bash
export SIFTBOX_READER_EMAIL=you@example.com
export SIFTBOX_READER_PASSWORD=a-long-enough-password
bin/setup                    # its db:prepare seeds the account from those two
bin/rails sample_data:load   # development only, gives the feed something to show
bin/dev
```

The authentication generator deliberately ships no sign-up flow, so the seeds
create the only account, from `SIFTBOX_READER_EMAIL` and
`SIFTBOX_READER_PASSWORD`. Nothing here is encrypted and no key is needed:
`db:prepare` loads the seeds whenever it creates the database, so a rebuilt
volume gets the account back from the same two variables. Seeds create the
account and never update it, so changing the password here does nothing to an
account that already exists; that is deliberate, since the reader may have
changed it through the reset flow. On a clone whose development database is
already there, `db:prepare` migrates rather than creates and so runs no seeds —
export the two variables and run `bin/rails db:seed` once by hand.

See `CLAUDE.md` and `.claude/rules` for the conventions this codebase
follows, and `bin/ci` for what has to pass.

## Receiving mail

`SIFTBOX_INBOUND_ADDRESS` is the address subscriptions get pointed at. It is
shown in the end-of-feed note and the empty state, and defaults to a
placeholder until the inbound domain is settled.

### Postmark

1. Create a Server in Postmark. Its Default Inbound Stream has a hash-based
   address you can use immediately.
2. For a real address, set an Inbound Domain on the stream and add an MX
   record pointing at `inbound.postmarkapp.com`, priority `10`. A dedicated
   subdomain is preferable to the root, so ordinary mail is unaffected.
3. Set the inbound webhook to:

   ```
   https://actionmailbox:PASSWORD@your-host/rails/action_mailbox/postmark/inbound_emails
   ```

4. **Tick "Include raw email content in JSON payload."** Action Mailbox needs
   the raw message, and without this the ingress fails with no obvious cause.

`PASSWORD` is `RAILS_INBOUND_EMAIL_PASSWORD`, which Action Mailbox
authenticates every delivery against. Generate a long random one; Action
Mailbox compares it in constant time, and changing it means changing the
Postmark webhook URL in the same sitting.

Postmark retries a failed inbound webhook 10 times over intervals growing
from 1 minute to 6 hours, so ingestion has to be idempotent — a partial
unique index on `newsletters.message_id` handles that. A `403` stops retries
permanently, which is the way to reject mail you never want.

### Locally

The ingress is armed in production only, so the webhook endpoint answers 404
everywhere else.

Use the conductor at `/rails/conductor/action_mailbox/inbound_emails` rather
than a tunnel — it creates inbound emails directly and routes them through
the real mailbox, so it needs no ingress. The highest-fidelity test is to
forward a real newsletter from your mail client *as an attachment* to get the
`.eml`, then paste its raw source into the conductor — that exercises the
mailbox against real newsletter MIME, which is where the surprises are.

## Deploying

`docs/deploying.md` is the runbook — the steps in the order they depend on
each other, worked through against a Hetzner host. What follows here is the
part worth understanding before running any of it.

The Kamal files declare what the app needs and, since the first deploy, where
it runs: `siftbox.co` on a Hetzner host. Every one of these variables fails
quietly rather than loudly, except the first, which stops the app dead:

| Variable | Missing means |
|---|---|
| `SECRET_KEY_BASE` | Rails has nothing to sign session cookies or reset tokens with and raises rather than serving. Changed rather than missing, the reader is signed out and any reset link in flight is void |
| `RAILS_INBOUND_EMAIL_PASSWORD` | Action Mailbox has nothing to authenticate against, so every Postmark webhook 500s. Wrong rather than missing, every one is a 401 with nothing in the log to say why |
| `SIFTBOX_READER_EMAIL`, `SIFTBOX_READER_PASSWORD` | No account is created on a fresh volume, so there is no way to sign in. The boot log says `No reader account created` |
| `SIFTBOX_INBOUND_ADDRESS` | The feed tells the reader to subscribe to `example.com` |
| `POSTMARK_SMTP_TOKEN` | Password reset silently fails — the only way back in |
| `SIFTBOX_MAIL_FROM` | Reset mail is rejected unless it is a Postmark sender signature |
| `SIFTBOX_HOST` | Reset links point at localhost |
| `SIFTBOX_TIME_ZONE` | Defaults to London; decides where the feed's day breaks |
| `SIFTBOX_WAITLIST` | Defaults to off: `/` sends a signed-out visitor to sign in and a signup answers 404. siftbox.co sets it to `true`; so does a development environment that wants the landing page (`SIFTBOX_WAITLIST=true bin/dev`) |

Every secret goes in `.kamal/secrets-common`, which is gitignored. Kamal reads
that file before `.kamal/secrets` with no flags, so `bin/kamal deploy` picks
them up without anything being exported into the shell first. Note the merge
order: Kamal applies `.kamal/secrets` over the top, so naming a variable in
both takes the value from the committed file, not the real one — which is why
`.kamal/secrets` names them in comments and assigns nothing.

Kamal refuses to deploy when a name in `env.secret` is in neither file, so a
name left out is loud. A wrong value is not, which is what the smoke test in
`docs/deploying.md` step 8 is for. That document lists every name, and what
each one does.

There is no database server to run. The four databases are SQLite files under
`storage/`, on the same mounted volume as the Active Storage blobs — so that
one path is the whole of this app's state, and backing it up backs up
everything.

### Outbound network — a deploy step this app cannot do for itself

Ingest fetches the images newsletters link to, which means URLs written by
anyone who can email the inbound address decide where this app makes
requests. `Newsletter::ImageDownload::Destination` refuses anything that
resolves off the public internet and hands back the address it checked, so
the connection goes there rather than to whatever a second DNS lookup might
answer.

**That is the application layer only.** The stronger control is an egress
rule on the host, blocking outbound traffic from the app container to
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8` and
`169.254.0.0/16` — the last of those being where cloud providers serve
instance credentials. Kamal does not install one, and nothing in this
repository will: it is a firewall or Docker network rule on the host, and it
has to be done by hand when the host is chosen.

It is worth doing even though the code checks already: it holds for any
outbound request the app ever grows, not only this one fetcher, and it does
not depend on the checks staying correct through future edits. Until then,
the code is the only thing enforcing this.

`docs/deploying.md` has the ranges to block, and what is particular about
doing it on a Hetzner host.

### Deploy steps

One-off steps that do not install themselves:

```bash
bin/rails lead_images:backfill
```

Reads the lead image out of every newsletter stored before the column
existed. Without it the whole archive renders the feed's "no image in email"
box. Idempotent, so it is safe to run again.

```bash
bin/rails confirmations:preview
bin/rails confirmations:backfill
```

Holds the subscription confirmations sitting in mail stored before detection
existed — detection runs at ingest, so without this the pen is empty on the
first morning while every confirmation the reader has ever received is behind
it in the archive. Idempotent. Run the preview first: it is the same walk
inside a transaction that rolls back, and it prints what would be held. Mail
a published edition already cites is left alone, whatever its subject says.

The app was called `newsbox` until recently. If you are upgrading a running
deployment, rename its `NEWSBOX_*` variables to `SIFTBOX_*` in the same
release as the code, or the app boots on placeholder values. The Kamal
storage volume was renamed with them.

## Decisions worth knowing

**Sanitizing happens at render, not at ingest.** `NewslettersHelper#newsletter_body`
runs the stored HTML through Action View's `sanitize`, which returns an
already-safe string — so nothing in the app calls `html_safe` or `raw` on
reader-supplied content. Tuning the allowlist in `Newsletter::Body` applies to
the whole archive immediately, with no cached column to reprocess.

**Images are self-hosted.** Everything a newsletter carries inside the
message (`cid:` references) is stored with Active Storage during ingest, and
everything it hotlinks is fetched by `Newsletter::RemoteImagesJob` just
after — in both cases the reference in the body is rewritten to a path this
app serves. So opening a newsletter makes no request to the sender, which is
the only way to stop an open being tracked: a tracking pixel that declares
no size is indistinguishable from a real image, and `Newsletter::TrackingPixelScrubber`
only catches the ones that declare 2px or less. It also means the archive
keeps its images once senders' CDNs stop serving them.

The sender still learns the message was processed, because the server
fetches once at delivery. That is what Apple Mail Privacy Protection and
Gmail's image proxy do too, and delivery is something an ESP already knows.

A download that fails leaves the `src` pointing where it did, so the reader
still sees the image — which is why the CSP keeps `img-src https:` and the
`same-origin` referrer policy in the layout still earns its place. The same
is true of a source past `Newsletter::RemoteImages::MAX_IMAGES`: nothing
bounds how many `<img>` tags a sender writes, and each one costs a request
and up to `MAX_BYTES` of disk on a queue three threads wide, so the count is
capped and the overflow stays hotlinked.

`Newsletter::ImageDownload` is the part to read before changing any of this:
it fetches attacker-supplied URLs from inside the network, so it checks
resolved addresses rather than hostnames, re-checks every redirect, and caps
redirects, bytes and time. Read `Destination` with the IPv6 forms in mind —
`::ffff:169.254.169.254` is the metadata address wearing a different hat, and
`IPAddr`'s `loopback?` and `link_local?` do not see through it. That is why
IPv6 gets an allowlist of global unicast rather than another denied prefix.

**Turbo's hover prefetching is off in the layout.** It was there because
opening a newsletter used to mark it read, so a prefetch wrote. Read state is
retired and nothing writes on a GET now, but the tag stays for a different
reason: an archive row points at an original, and prefetching one on hover
pulls a body that runs to hundreds of kilobytes for a row nobody opened.

**The feed is bounded to seven days**, which is what its end-of-feed copy
claims. Showing more history needs a pagination design first.

**Each newsletter's lead image is captured at ingest**, into
`newsletters.lead_image_url`, so the feed can render a thumbnail per row
without loading a `body_html` to find one — `Newsletter::FEED_COLUMNS` exists
precisely to keep the index off that column. Extraction runs *after*
`Newsletter::InlineImages`, which rewrites `cid:` references to app paths;
reading the lead first would store a URL no browser can resolve.

**The landing page is the only public write path.** It is guarded four ways:
an off-screen honeypot answered exactly like a real signup, a rate limit
counting in `Rails.cache`, strong parameters, and treating a duplicate address
as success — the unique index raises and `WaitlistSignup#join` rescues, rather
than a uniqueness validation reporting a clash and answering a question about
someone else's address. Nothing is emailed: the copy promises exactly one
message, and a confirmation would break that on day one.

**`noindex, nofollow` is not site-wide.** The layout emits it unless a
template sets `content_for :indexable`, which only the landing page does.

## Deferred

Archiving, search and tagging are all deliberately out of v1. The design
handoff shows `ARCHIVED` in the feed header, `ARCHIVE` in the reader top bar
and a search icon; none of them are built. Both bars are flex rows, so they
degrade cleanly with the controls absent. Archiving and search are roughly a
migration and thirty lines each — with one note for whoever adds search: this
app is SQLite, so `LIKE`, which is already case-insensitive for ASCII, not the
`ILIKE` the handoff assumes.

The handoff's sponsor block (its §5.4) is not built and is not planned. There
is no way to identify a sponsor section in arbitrary newsletter HTML without a
heuristic per sender.

Multiple readers would take three steps: a wildcard inbound domain
(`*.your-domain`), a token address per user, and resolving the `To:` address
to a user in `NewslettersMailbox`. Until then `Feed` is deliberately not
scoped to a user — with one account the authentication gate is the scope, and
a `user_id` nothing filters on would be theatre.
