# newsbox

Receives newsletter emails at one dedicated address via Action Mailbox and
Postmark, and presents them as a clean reading feed for a single reader.

Two screens: a feed grouped by the day mail arrived, and a reader that strips
the sender's styling and re-renders the newsletter in the app's own
typography. There is an escape hatch — "View original" — that shows the
sender's HTML in a sandboxed iframe.

## Getting started

```bash
bin/setup
NEWSBOX_EMAIL=you@example.com NEWSBOX_PASSWORD=... bin/rails db:seed
bin/rails sample_data:load   # development only, gives the feed something to show
bin/dev
```

The authentication generator deliberately ships no sign-up flow, so `db:seed`
creates the only account. See `CLAUDE.md` and `.claude/rules` for the
conventions this codebase follows, and `bin/ci` for what has to pass.

## Receiving mail

`NEWSBOX_INBOUND_ADDRESS` is the address subscriptions get pointed at. It is
shown in the feed header and the empty state, and defaults to a placeholder
until the inbound domain is settled.

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

`PASSWORD` is `action_mailbox.ingress_password` in credentials, or the
`RAILS_INBOUND_EMAIL_PASSWORD` environment variable. Generate a long random
one; Action Mailbox compares it in constant time.

This repository carries no `config/credentials.yml.enc`. Run
`bin/rails credentials:edit` once to generate your own along with a master
key — committing an encrypted file whose key lives on someone else's machine
would just leave you something you cannot open.

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

The Kamal files declare what the app needs but not where it runs — no host,
no database accessory. Those are still open. What is wired up is the list of
variables, because every one of them fails quietly rather than loudly:

| Variable | Missing means |
|---|---|
| `RAILS_INBOUND_EMAIL_PASSWORD` | Every Postmark webhook 500s; newsletters are lost once Postmark stops retrying |
| `NEWSBOX_INBOUND_ADDRESS` | The feed tells the reader to subscribe to `example.com` |
| `POSTMARK_SMTP_TOKEN` | Password reset silently fails — the only way back in |
| `NEWSBOX_MAIL_FROM` | Reset mail is rejected unless it is a Postmark sender signature |
| `NEWSBOX_HOST` | Reset links point at localhost |
| `NEWSBOX_TIME_ZONE` | Defaults to London; decides where the feed's day breaks |

There is no database server to run. The four databases are SQLite files under
`storage/`, on the same mounted volume as the Active Storage blobs — so that
one path is the whole of this app's state, and backing it up backs up
everything. The only thing still to decide is the proxy host in
`config/deploy.yml`.

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
`same-origin` referrer policy in the layout still earns its place.
`Newsletter::ImageDownload` is the part to read before changing any of this:
it fetches attacker-supplied URLs from inside the network, so it checks
resolved addresses rather than hostnames, re-checks every redirect, and caps
redirects, bytes and time.

**Opening a newsletter marks it read**, which means `GET /newsletters/:id`
writes. Turbo's hover prefetching is therefore turned off in the layout;
without that, hovering a feed row marks it read without opening it.

**The feed is bounded to seven days**, which is what its end-of-list copy
claims. Showing more history needs a pagination design first.

## Deferred

Archiving, search and tagging are all deliberately out of v1. Archiving and
search are roughly a migration and thirty lines each — the filter bar is a
flex row, so it degrades cleanly with them absent.

Multiple readers would take three steps: a wildcard inbound domain
(`*.your-domain`), a token address per user, and resolving the `To:` address
to a user in `NewslettersMailbox`. Until then `Feed` is deliberately not
scoped to a user — with one account the authentication gate is the scope, and
a `user_id` nothing filters on would be theatre.
