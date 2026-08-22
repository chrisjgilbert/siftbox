# Deploying, step by step

A first deploy in the order the steps actually depend on each other. The
worked example is `siftbox.co` on a Hetzner VM; substitute your own domain
and host.

`README.md` covers *why* several of these matter — the variables that fail
quietly, what lives on the volume, and the egress rule. This is the order to
do them in.

## 1. DNS

Two records, on purpose:

| Record | Name | Value | Why |
|---|---|---|---|
| A | `siftbox.co` | `46.224.179.132` | Where the app is served |
| MX | `news.siftbox.co` | `inbound.postmarkapp.com`, priority `10` | Where newsletters arrive |

The two are unrelated lookups. A browser asks for the A record; a mail
server delivering to `news@news.siftbox.co` asks for the MX and never sees
the A record at all.

Inbound mail goes to a **subdomain** so that the MX does not claim every
address at `siftbox.co` — an MX on the root would send `chris@siftbox.co`
into the newsletter feed too. The web app on the root carries no such
consequence, which is why the app is at `siftbox.co` and the mail at
`news.siftbox.co`. Serving the app from `app.siftbox.co` instead works
equally well; it is `proxy.host`, `SIFTBOX_HOST` and the webhook URL that
have to agree, and the MX is unaffected either way. Rails sets its session
cookie host-only, so nothing is shared with `news.` either way.

If the VM has an IPv6 address you can add an AAAA record — kamal-proxy
already listens on `[::]:443` — but see step 7 first, because IPv6 changes
what the egress rule has to cover. What you must not do is leave a stale
AAAA pointing somewhere else while the A record points at the VM: clients
that prefer IPv6 will all take the wrong path.

### Behind Cloudflare

Cloudflare can proxy the A record (it also removes the usual "no CNAME at
the apex" limitation via CNAME flattening). Three things to get right:

- **SSL/TLS mode must be Full or Full (strict).** `production.rb` sets
  `force_ssl`, so "Flexible" — where Cloudflare talks plain HTTP to the
  origin — redirects forever. It looks like the site hanging, not an error.
- **Deploy once DNS-only (grey cloud) first**, so Let's Encrypt can answer
  its own challenge and Kamal gets a certificate. Turn proxying on after.
  Proxied before that certificate exists, the host answers `525`: Cloudflare
  reaches the VM, kamal-proxy has no route for the hostname yet, the TLS
  handshake fails, and Cloudflare reports it as an origin SSL error rather
  than as the missing route it is.
- **Watch the webhook.** Postmark's POST is an automated request from a
  machine, and Cloudflare's bot or WAF rules can block it. The only symptom
  is newsletters silently not arriving, so if Postmark's Activity view shows
  failures the app never logged, add a skip rule for
  `/rails/action_mailbox/`.

MX records cannot be proxied — Cloudflare only proxies A, AAAA and CNAME —
so inbound mail bypasses all of this.

A cost of staying DNS-only: the origin IP is public, and scanners find it
within minutes — `/.env`, `/config.json` and the like. Rails answers 404 and
there is nothing to take, but the log noise is the trade for Let's Encrypt
renewing itself without a proxy in the way.

## 2. Postmark

1. Create a Server. Its Default Inbound Stream has a hash-based address that
   works immediately, which is worth testing with before DNS propagates.
2. Set the Inbound Domain on that stream to `news.siftbox.co`.
3. Set the inbound webhook to:

   ```
   https://actionmailbox:PASSWORD@siftbox.co/rails/action_mailbox/postmark/inbound_emails
   ```

4. **Tick "Include raw email content in JSON payload."** Action Mailbox
   needs the raw message, and without this the ingress fails with no obvious
   cause.
5. Add a **sender signature** for the address password-reset mail comes from.
   Postmark rejects sends from anything else, and reset mail is the only way
   back into the account.

Generate `PASSWORD` as a long random string. It goes in credentials in step 3,
and the same value goes in this webhook URL.

## 3. Credentials

The ingress password lives in credentials, under `action_mailbox`:

```bash
bin/rails credentials:edit
```

```yaml
action_mailbox:
  ingress_password: the PASSWORD from step 2
```

Action Mailbox does read a `RAILS_INBOUND_EMAIL_PASSWORD` variable, but only
when the credential is unset — so do not set both. With the credential
present the variable is ignored, and a mismatch shows up as a 401 on every
webhook with nothing to say why.

`config/credentials.yml.enc` is committed; `config/master.key` is not. Kamal
reads the key off disk as `RAILS_MASTER_KEY`, so the machine you deploy from
needs a copy. Never commit it.

## 4. config/deploy.yml

Already filled in: the host, `cjgilbert/siftbox` on Docker Hub, `siftbox.co`
as `proxy.host`, and the four `SIFTBOX_*` variables. `SIFTBOX_MAIL_FROM` is
the one to check against reality — it has to match the sender signature you
verified in step 2, or every password reset is rejected.

`service: siftbox` and the volume `siftbox_storage` are what keep this app
apart from the others on the box, so leave both alone unless something else
there already claims those names.

Pointing `image` at a different registry: Kamal prefixes `registry.server`
onto it, so `image` is the path within the registry rather than the full
reference. Naming the registry in both gives you
`ghcr.io/ghcr.io/user/siftbox`.

The two secrets that live neither in credentials nor on disk go in
`.kamal/secrets-common`, which is gitignored. Kamal reads it before
`.kamal/secrets` with no flags, so nothing needs exporting into the shell:

```bash
KAMAL_REGISTRY_PASSWORD=...
POSTMARK_SMTP_TOKEN=...
ANTHROPIC_API_KEY=...
```

`ANTHROPIC_API_KEY` is what the morning edition is written with, and it is
named in `env.secret` so Kamal passes it into the container. It spends money
every day the job runs — see step 9.

Do not restate those two in `.kamal/secrets`. That file is merged over the
top, so a `KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD` passthrough
resolves against an unset shell variable and overwrites the real value with
an empty string.

If the host is arm64 and the target is amd64, set `builder.remote` to the
target host rather than building through emulation:

```yaml
builder:
  arch: amd64
  remote: ssh://root@the-vm
```

`proxy.ssl: true` is already set, so Kamal gets a Let's Encrypt certificate
for `proxy.host` on the first deploy. That is also why step 1 comes first —
the certificate cannot be issued before the A record resolves.

Nothing to change for storage or the queue: the volume
`siftbox_storage:/rails/storage` is already declared, and
`SOLID_QUEUE_IN_PUMA: true` runs the worker inside Puma, which is what
fetches newsletter images.

## 5. First deploy

```bash
bin/kamal setup
```

The container entrypoint runs `db:prepare` when it starts the server, so the
four SQLite databases are created on the volume without a separate step.

## 6. Create the reader account

Put the account in credentials, back in step 3:

```yaml
reader:
  email_address: you@example.com
  password: ...
```

`db:prepare` loads `db/seeds.rb` whenever it creates the database, so with
that block present the first container boot creates the account by itself and
a rebuilt volume gets it back the same way. Without it, boot logs
`No reader account created` and carries on rather than failing.

If the databases already exist — the credential was added after the first
deploy, say — seeds will not have run. Do it once by hand:

```bash
bin/kamal app exec --reuse "bin/rails db:seed"
```

Seeds create the account and never update it. Changing the password in
credentials does nothing to an account that already exists, because the
reader may have changed it through the reset flow and rewriting it here would
lock them out. To change an existing password, do it in the console.

There is no sign-up flow, by design. This is the only account.

### Measure the images already stored

Run once, on the first deploy that carries `image_processing`:

```bash
bin/kamal app exec --reuse "bin/rails images:analyze"
```

Active Storage measures an image with libvips, which the app had no gem for
until now, so every blob stored before this deploy is flagged analysed and
carries no width or height. Rails will not look at an analysed blob again, so
nothing re-measures them on its own and the reader keeps the shifting text the
sizes exist to stop. Anything attached after this deploy is measured by its
own `AnalyzeJob` and needs no task.

Safe to run more than once: a blob that already has a width is skipped, and a
blob libvips cannot read is reported and left as it is.

## 7. The egress rule — Hetzner specifics

Ingest fetches the images newsletters link to, so URLs written by anyone who
can email the inbound address decide where this app makes outbound requests.
`Newsletter::ImageDownload::Destination` refuses anything resolving off the
public internet, but the durable control is at the network layer. See
"Outbound network" in `README.md` for why it is worth having both.

Two things specific to Hetzner:

- **Metadata lives at `169.254.169.254`**, the address the application-level
  checks exist to block. It serves instance configuration to anything that
  can reach it locally.
- **Hetzner Cloud Firewalls filter inbound traffic only.** They will not do
  this, so it has to be `nftables`/`iptables` on the box, or a Docker network
  the container cannot route out of.

Block outbound from the app container to:

```
10.0.0.0/8  172.16.0.0/12  192.168.0.0/16  127.0.0.0/8  169.254.0.0/16
```

If the VM has IPv6, cover the v6 equivalents too — `::1/128`, `fc00::/7`
(unique local), `fe80::/10` (link local) — since a hostile AAAA record is
just as easy to publish as an A record.

Leave the private ranges your own infrastructure needs reachable, if any.
Today the app talks to Postmark and to senders' image CDNs, both public.

**On a shared host, do not apply these ranges host-wide.** Docker bridge
networks sit inside `172.16.0.0/12` — `172.17.0.0/16` for the default bridge
and a `172.18.0.0/16`-and-up per user-defined network — so a blanket rule cuts
every container on the box off from its database. The rule has to match on
siftbox's own container or network as the source, not on the host's whole
`FORWARD` chain. Check what else is running first:

```bash
docker ps --format "{{.Names}}"
ip -4 addr show | grep -E "docker0|br-"
```

## 8. Smoke test

1. Sign in at `https://siftbox.co`.
2. Subscribe to something with the address in the feed header, or forward a
   real newsletter to it.
3. Open it and confirm the images have `src="/newsletters/…/images/…"` rather
   than the sender's CDN. That is the whole feature working end to end:
   webhook accepted, mailbox routed, job ran, images fetched and rewritten.
4. Check "View original" renders too — it is the sandboxed frame, and it
   embeds images as data URIs rather than fetching them.
5. Subscribe to something that double-opts-in, and follow the confirmation
   the whole way: it should be held out of the feed, listed under **Awaiting
   confirmation** on `/subscriptions`, and announced on the edition page as
   "1 subscription awaiting confirmation". Open it, click the sender's own
   confirm button inside the frame, then press **Done**. The app cannot see
   that click — the frame has an opaque origin — so Done is what clears the
   row and the notice. Nothing here has been through a real double-opt-in
   yet; this is the step that finds out whether the phrase set recognises one
   in the wild. If it does not, the mail is in the feed instead and the fix is
   `Newsletter::Confirmation::PHRASES`.

The ingress is armed in production only, so the webhook endpoint answers 404
in development by design. Locally, use the conductor at
`/rails/conductor/action_mailbox/inbound_emails` instead — see `README.md`.

## 9. The morning edition

`config/recurring.yml` schedules `Edition::CompositionJob` for `every day at
7am Europe/London`. The zone is named in the schedule itself, so the reader
gets the edition at seven on both sides of a clock change rather than at
seven-in-whatever-offset-it-was-written-in.

Solid Queue's scheduler is what fires it, and the scheduler starts inside
Puma alongside the workers because `SOLID_QUEUE_IN_PUMA` is already set — so
there is no extra process to run. **But the task does not install itself.**
The row in `solid_queue_recurring_tasks` is written when the scheduler boots,
which means the schedule only exists after a deploy that carries it. Confirm
it once, after that deploy:

```bash
bin/kamal app exec --reuse "bin/rails runner 'puts SolidQueue::RecurringTask.all.map(&:to_s)'"
```

Two entries, one of them `Edition::CompositionJob.perform_later() [ 0 7 * * *
Europe/London ]`. Nothing there means the scheduler did not start; the app
logs say why.

**A second recurring task joined it.** `poll_blogs` runs `Blog::PollJob`
every hour at minute 20, asking each blog on the roster whether its feed has
anything new. It installs itself the same way and needs confirming the same
way — the command above should list three entries once it has been deployed,
not two.

Nothing polls until a blog exists. Blogs are added on the Subscriptions page,
under Blogs: paste the feed address, or the blog's home page and siftbox will
find the feed from it.

The feed is sampled while you wait — about a second, and five for the largest
real feed measured — which is what makes a refusal something you are told
rather than something you work out later. The reading itself happens behind
you: the row appears at once saying "Not checked yet" and fills in within
seconds. It does not wait for the top of the hour.

Four things get refused there, each with a reason on the page:

- **A link aggregator.** Hacker News, lobste.rs and Reddit publish items whose
  whole body is a link back to their own thread — a median of eight
  characters. `docs/blogs-rss.md` sets out why an edition composed from those
  is unreadable. A feed fewer than half of whose items carry a hundred
  characters of prose is turned away. That threshold sits between an
  aggregator's eight and the three hundred or so a blog publishing excerpts
  carries, so a summary-only blog is still in scope.
- **An address that is not a feed and announces none.** Usually a typo, or a
  page whose feed link has gone. A page that does announce one is followed to
  it, so pasting a home page works.
- **An address that could not be read at all** — wrong host, refused
  connection, or anything `Download` will not reach, which includes every
  private address.
- **A feed with no items in it yet.** A blog set up the day before its first
  post: come back once it has published.

Note what is *not* refused: a Planet-style rollup that syndicates whole posts
reads exactly like a blog to this test, because as far as the test is
concerned it is one. It is out of scope in `docs/blogs-rss.md` and unenforced
here.

The first poll of a new blog stores its whole back catalogue in the archive
but keeps everything older than a week out of the edition window, so adding a
long-running blog does not put years of writing into the next morning's
edition.

Removing a blog on the same page destroys its posts, and the citations in
published editions that name them. That is the trade of removing a source
rather than muting one.

The first firing has three possible outcomes and they read differently in
the log:

- **An edition.** A minute or two of model time and a row in `editions`. The
  PRD's arithmetic says about $0.45; nobody has measured a real run yet, and
  the token counts stored on each edition are where the real figure comes
  from.
- **`no newsletters since the last edition closed; nothing to compose`.** An
  empty window skips silently by design — no edition, no error. The line
  exists so that a quiet inbox and a scheduler that never fired do not look
  identical from here.
- **`no edition composed: …`**, at error level. Something the run cannot fix
  by trying again: the model declined the window, the edition ran past the
  token ceiling, or the API refused the request. A model that could not be
  reached is the one failure that does retry, four times, fifteen minutes
  apart, and is recorded as a failed job if it never lands.

Whatever happens, nothing is lost. The window is a high-water mark, so a
morning that produces no edition leaves its newsletters above the mark and
tomorrow's window covers them.

Worth knowing on the first deploy only: **No. 1 reaches back one day**
(`Edition::Window::FIRST_WINDOW`), not over the whole archive. Mail stored
before that belongs to no edition and stays where it is, in the originals
archive.

To compose one by hand — a morning missed while the key was wrong, say:

```bash
bin/kamal app exec --reuse "bin/rails runner 'Edition::CompositionJob.perform_now'"
```

It covers everything since the last edition closed, so on a day that already
has one it usually finds an empty window and skips. It also costs the same as
the scheduled run.

If this app ever moves job processing onto its own host — the commented-out
`job:` role in `config/deploy.yml` — take care that only one supervisor runs
the scheduler, or two of them fire at 07:00. Solid Queue's unique index on
`(task_key, run_at)` already collapses that into one enqueue, and the unique
indexes on `editions.number` and `editions.published_on` are the backstop
under it, but neither is a reason to run two.

## Backups

Everything is one path. The four SQLite databases and every stored image sit
under `storage/` on the `siftbox_storage` volume, so backing that up backs up
the whole app, and nothing outside it needs backing up at all.

Worth knowing that it now grows: self-hosting images means a heavily
illustrated newsletter costs real disk, bounded per newsletter by
`Newsletter::RemoteImages::MAX_IMAGES` and
`Newsletter::ImageDownload::MAX_BYTES`.

### Take one before the read-state migration

`RemoveReadAtFromNewsletters` drops `newsletters.read_at`. It reverses in
shape — rolling back adds the column back — but not in content: the
timestamps are gone, and every newsletter comes back as unread. Nothing in
the app reads them any more, so what is lost is only the record of which mail
had been opened, but it is lost for good. Back the volume up before the
staging deploy and again before the production one, and expect the rollback
plan for this release to be "restore", not "roll back the migration".

## Still open

- `Feed` is not scoped to a user. With one account the authentication gate is
  the scope; see the note at the end of `README.md` for what multiple readers
  would take.
- A failed image fetch is not retried, so an image whose host was briefly
  unreachable at ingest stays hotlinked.
