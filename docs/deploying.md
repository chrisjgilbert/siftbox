# Deploying, step by step

A first deploy in the order the steps actually depend on each other. The
worked example is `siftbox.co` on a Hetzner VM; substitute your own domain
and host.

`docs/operating.md` covers *why* several of these matter — the variables that fail
quietly, what lives on the volume, and the egress rule. This is the order to
do them in.

`config/deploy.yml` is a template and names no deployment. What names one is
`config/deploy.production.yml`, which is gitignored, which step 4 writes, and
which Kamal merges over the template when a command is given `-d production`.
Every `bin/kamal` command below carries that flag for the same reason. A
self-hoster who would rather put their values straight into
`config/deploy.yml` can: drop the `-d production` from every command here and
skip the destination file. Nothing else about the runbook changes — but that
file is committed, so their host and registry account become a tracked
modification that `git commit -a` would publish and that the next pull
conflicts with. The destination file is what avoids both.

## 1. DNS

Two records, on purpose:

| Record | Name | Value | Why |
|---|---|---|---|
| A | `siftbox.co` | `<the host's address>` | Where the app is served |
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

Generate `PASSWORD` as a long random string. It goes in the secrets in step 3,
as `RAILS_INBOUND_EMAIL_PASSWORD`, and the same value goes in this webhook URL.

## 3. Secrets

This app carries no encrypted credentials. Everything secret reaches the
container as an environment variable, named in `env.secret` in
`config/deploy.yml` and valued in `.kamal/secrets-common`, which step 4 writes:

| Variable | What it is |
|---|---|
| `KAMAL_REGISTRY_PASSWORD` | An access token for the image registry, rather than the account password |
| `SECRET_KEY_BASE` | What Rails signs session cookies and password-reset tokens with. `bin/rails secret` generates one |
| `RAILS_INBOUND_EMAIL_PASSWORD` | The `PASSWORD` from step 2, which Action Mailbox authenticates every Postmark webhook against |
| `POSTMARK_SMTP_TOKEN` | The Postmark server token, which sends password-reset mail |
| `SIFTBOX_READER_EMAIL`, `SIFTBOX_READER_PASSWORD` | The only account, created at first boot — step 6 |
| `ANTHROPIC_API_KEY` | What the morning edition is written with — step 9 |
| `HONEYBADGER_API_KEY` | Where errors are reported |

Two of them are worth a sentence each.

`RAILS_INBOUND_EMAIL_PASSWORD` has to match the password in the webhook URL
from step 2 exactly. Change one and change the other in the same sitting, or
every delivery is refused.

`SECRET_KEY_BASE` is generated only for a deployment that has never run. One
that is already running carries its existing value across, because a new one
signs the reader out and voids any password-reset link in flight. That value
used to be derived from the encrypted credentials, so read it out before this
release removes them — `bin/rails credentials:show` on the machine that holds
`config/master.key`, the `secret_key_base` key — and put it in
`.kamal/secrets-common`. Once the credentials file is gone it cannot be
recovered, and the sign-out is the only way through.

`config/master.key` is no part of a deploy any more, and neither is
`RAILS_MASTER_KEY`. A clone made before the credentials file was removed may
still hold a key; it is gitignored, nothing reads it, and it can go once the
values above are out.

## 4. config/deploy.production.yml

`config/deploy.yml` is committed and names no deployment: it carries the
service name, the volume, the proxy block, the health check, the `env.secret`
names and the `SIFTBOX_*` names with placeholder values. Everything that names
this deployment goes in `config/deploy.production.yml` beside it, which is
gitignored and which a fresh clone therefore does not have:

```yaml
image: <the registry account>/siftbox

servers:
  web:
    hosts:
      - <the host's address>

proxy:
  host: siftbox.co

registry:
  username: <the registry account>

env:
  clear:
    SIFTBOX_INBOUND_ADDRESS: news@news.siftbox.co
    SIFTBOX_TIME_ZONE: London
    SIFTBOX_HOST: siftbox.co
    SIFTBOX_MAIL_FROM: siftbox@siftbox.co
    SIFTBOX_WAITLIST: "true"

builder:
  arch: amd64
  remote: ssh://root@<the host's address>
```

Kamal deep-merges that over the template, so the file carries only what
differs, and two things follow from how the merge works. A hash in both merges
key by key: the `env.clear` above adds to and overrides the template's rather
than replacing it, so a name left out here keeps its placeholder value — which
is why every `SIFTBOX_*` name is listed even where the value happens to match.
An array in both is replaced whole: the `hosts` list here *is* the list rather
than an addition to the template's.

`bin/kamal config -d production` is how to confirm the destination file was
picked up at all: it prints the hosts, the image repository and the builder
from the merged config. It prints neither `proxy` nor `env`, so the two values
below that a typo hides — `proxy.host` and `SIFTBOX_MAIL_FROM` — have to be
read in the file itself. After a deploy, one of them can be read back off the
container:

```bash
bin/kamal app exec -d production --reuse "printenv SIFTBOX_MAIL_FROM"
```

`SIFTBOX_MAIL_FROM` is the value to check against reality — it has to match
the sender signature verified in step 2, or every password reset is rejected.
`SIFTBOX_WAITLIST` is what puts the landing page and the waitlist on `/`, and
off is the default, so dropping it makes the landing page disappear on the
next deploy.

`builder.remote` builds the image on the target host rather than through
emulation, and belongs here rather than in the template because it is a fact
about the machine deploying, not about the app: drop it if the deploy machine
is amd64 already.

`service: siftbox` and the volume `siftbox_storage` stay in the template.
They are what keep this app apart from the others on the box, so leave both
alone unless something else there already claims those names.

Pointing `image` at a different registry: Kamal prefixes `registry.server`
onto it, so `image` is the path within the registry rather than the full
reference. Naming the registry in both gives you
`ghcr.io/ghcr.io/user/siftbox`.

The values behind `env.secret` go in `.kamal/secrets-common`, which is
gitignored and which Kamal reads whether or not the command names a
destination, so nothing needs exporting into the shell. Every name from
step 3, and all of them:

```bash
KAMAL_REGISTRY_PASSWORD=...
SECRET_KEY_BASE=...
RAILS_INBOUND_EMAIL_PASSWORD=...
POSTMARK_SMTP_TOKEN=...
SIFTBOX_READER_EMAIL=...
SIFTBOX_READER_PASSWORD=...
ANTHROPIC_API_KEY=...
HONEYBADGER_API_KEY=...
```

A name that is missing fails loudly: Kamal looks every `env.secret` name up
when it writes the container's env file and stops with `Secret
'SECRET_KEY_BASE' not found in .kamal/secrets-common` — it names the files it
actually read — rather than booting the new container. The image has been
built and pushed by then, so this is not free — but the running container is
untouched and no wrong value reaches it. A value that is wrong fails silently,
and later. A mistyped `RAILS_INBOUND_EMAIL_PASSWORD` is a 401 on every webhook
with nothing in the log to say why; a wrong `POSTMARK_SMTP_TOKEN` surfaces the
first time someone needs a password reset; a fresh `SECRET_KEY_BASE` signs the
reader out. That asymmetry is what step 8 is for — a deploy that runs proves
the names, and only the smoke test proves the values.

Running without a Honeybadger account is fine, and an empty value is how: the
name is present, so Kamal deploys, and the gem treats an empty key exactly as
it treats none at all — it logs that the key is missing, once per report, and
sends nothing.

```bash
HONEYBADGER_API_KEY=
```

`ANTHROPIC_API_KEY` spends money every day the composition job runs — see
step 9. An empty value there is not the same trade, and it is not a `KeyError`
either: Kamal writes the name into the container's env file whatever the value,
so the variable is set rather than absent and the `ENV.fetch` in
`app/models/edition/draft.rb` returns the empty string instead of raising. The
request goes out, the API refuses it, and `Edition::CompositionJob` discards
`Edition::Draft::Rejected` with `no edition composed: the request was refused`
in the worker log — once a morning, and there is no edition. Leaving the name
out of `.kamal/secrets-common` altogether is the loud version, and it stops the
deploy rather than the morning.

`.kamal/secrets-common` is the only secrets file this deployment needs, and the
only one it should have. Which file Kamal reads after it depends on the
destination — `.kamal/secrets.production` with `-d production`, the committed
`.kamal/secrets` without one — and the comments in `.kamal/secrets` set out
both traps that follow: a name restated in the second file overwrites the real
value with an empty string, and a value put in `.kamal/secrets` is not read at
all on a destination deploy, with nothing said about it either way.

`proxy.ssl: true` is already set, so Kamal gets a Let's Encrypt certificate
for `proxy.host` on the first deploy. That is also why step 1 comes first —
the certificate cannot be issued before the A record resolves.

Nothing to change for storage or the queue: the volume
`siftbox_storage:/rails/storage` is already declared, and
`SOLID_QUEUE_IN_PUMA: true` runs the worker inside Puma, which is what
fetches newsletter images.

## 5. First deploy

```bash
bin/kamal setup -d production
```

The container entrypoint runs `db:prepare` when it starts the server, so the
four SQLite databases are created on the volume without a separate step.

The containers this brings up are named `siftbox-web-production`: with a
destination, Kamal names both them and the kamal-proxy service it registers
`service-role-destination`. A deployment already running without a destination
is a separate thing to this one, however identical the values — see "Moving a
running deployment onto a destination" below.

## 6. Create the reader account

The account is two of the variables from step 3:

```bash
SIFTBOX_READER_EMAIL=you@example.com
SIFTBOX_READER_PASSWORD=...
```

`db:prepare` loads `db/seeds.rb` whenever it creates the database, so with both
set the first container boot creates the account by itself and a rebuilt volume
gets it back the same way — they belong to the deployment rather than to the
volume. Without them, boot logs `No reader account created` and carries on
rather than failing.

If the databases already exist — the variables were added after the first
deploy, say — seeds will not have run. Do it once by hand:

```bash
bin/kamal app exec -d production --reuse "bin/rails db:seed"
```

Seeds create the account and never update it. Changing
`SIFTBOX_READER_PASSWORD` does nothing to an account that already exists,
because the reader may have changed it through the reset flow and rewriting it
here would lock them out. To change an existing password, do it in the console.

There is no sign-up flow, by design. This is the only account.

### Measure the images already stored

Run once, on the first deploy that carries `image_processing`:

```bash
bin/kamal app exec -d production --reuse "bin/rails images:analyze"
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
`Download::Destination` refuses anything resolving off the
public internet, but the durable control is at the network layer. See
"Outbound network" in `docs/operating.md` for why it is worth having both.

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
6. Sign out, ask for a password reset, and confirm the mail arrives and its
   link works. Nothing else on this list touches `POSTMARK_SMTP_TOKEN` or
   `SIFTBOX_MAIL_FROM`, and both fail silently: the token is read with a
   default so the image can be built without it, and a From address Postmark
   has no signature for is rejected at send time. Reset mail is the only way
   back into an account with no sign-up flow, so a wrong value here is found
   either now or on the day it is needed. Signing back in afterwards is also
   what proves `SECRET_KEY_BASE` reached the container.

The ingress is armed in production only, so the webhook endpoint answers 404
in development by design. Locally, use the conductor at
`/rails/conductor/action_mailbox/inbound_emails` instead — see
`docs/operating.md`.

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
bin/kamal app exec -d production --reuse "bin/rails runner 'puts SolidQueue::RecurringTask.all.map(&:to_s)'"
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
bin/kamal app exec -d production --reuse "bin/rails runner 'Edition::CompositionJob.perform_now'"
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

## Moving a running deployment onto a destination

A deployment that was set up before `config/deploy.yml` became a template runs
containers named `siftbox-web`, and kamal-proxy holds `siftbox.co` for that
name. The first `-d production` deploy asks for `siftbox-web-production`, which
is a different service as far as both Docker and kamal-proxy are concerned. So
the old one has to go before the new one arrives. This is a one-off, and it
costs a minute or two of downtime.

`bin/kamal app remove` has to run against the config that still names the real
host, which means running it **before** the deploy machine pulls the change
that turns `config/deploy.yml` into a template. Pulled already, bring that one
file back for the length of the command:

```bash
git show <the commit before this change>:config/deploy.yml > config/deploy.yml
```

The order:

1. Write `config/deploy.production.yml` (step 4). It is gitignored, so it
   survives the pull and nothing reads it until a command asks for
   `-d production`.
2. `bin/kamal app remove` — no destination. **The app has to be running when
   this goes in.** Stopping a role behind the proxy runs `kamal-proxy remove`
   for it, which is what releases `siftbox.co` rather than leaving it held —
   but Kamal only runs that when it finds a container up for the currently
   running version, and says nothing when it does not. So boot it first
   (`bin/kamal app boot`) if it is stopped or crashed, or `siftbox.co` stays
   registered to `siftbox-web` and the deploy below asks kamal-proxy for a host
   it already holds. After the release it removes the app's containers, its
   images and the `.kamal/apps/siftbox` directory on the host. It does not
   touch volumes, so `siftbox_storage` and everything in it stay where they
   are. The site is down from here.
3. Pull the change, if it is not pulled already. If step 2 needed the line
   above, put the committed template back with
   `git checkout -- config/deploy.yml`.
4. `bin/kamal deploy -d production`. New containers, a new claim on
   `siftbox.co`, the same volume mounted at the same path. The certificate is
   re-issued for the same hostname.
5. Smoke test, step 8, and confirm the state came with it:

   ```bash
   bin/kamal app exec -d production --reuse "ls storage"
   ```

   Four `.sqlite3` files and their `-shm`/`-wal` companions, plus the Active
   Storage tree. An empty directory means the volume was not attached and the
   entrypoint built fresh databases beside it — stop and look at
   `volumes:` before signing in, because a sign-in would seed a new reader
   into the wrong place.

It is `bin/kamal app remove`, not `bin/kamal remove`. The second also removes
kamal-proxy itself, which on a shared host is serving the other apps there.

Nothing is lost in the gap. Postmark retries an inbound delivery for hours, so
newsletters arriving during the cutover land afterwards; a reader mid-page sees
an error and a reload fixes it. Do it at a quiet hour, and not at 07:00, when
the composition job runs.

## Backups

Everything is one path. The four SQLite databases and every stored image sit
under `storage/` on the `siftbox_storage` volume, so backing that up backs up
the whole app, and nothing outside it needs backing up at all.

Worth knowing that it now grows: self-hosting images means a heavily
illustrated newsletter costs real disk, bounded per newsletter by
`RemoteImages::MAX_IMAGES` and
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
  the scope; see the note at the end of `docs/operating.md` for what multiple
  readers would take.
- A failed image fetch is not retried, so an image whose host was briefly
  unreachable at ingest stays hotlinked.
