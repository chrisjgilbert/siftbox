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
server delivering to `newsletters@news.siftbox.co` asks for the MX and never
sees the A record at all.

Inbound mail goes to a **subdomain** so that the MX does not claim every
address at `siftbox.co` — an MX on the root would send `chris@siftbox.co`
into the newsletter feed too. The web app on the root carries no such
consequence, which is why the app is at `siftbox.co` and the mail at
`news.siftbox.co`. Serving the app from `app.siftbox.co` instead works
equally well; it is `proxy.host`, `NEWSBOX_HOST` and the webhook URL that
have to agree, and the MX is unaffected either way.

If the VM has an IPv6 address, add the AAAA record too — but see step 7
first, because IPv6 changes what the egress rule has to cover.

### Behind Cloudflare

Cloudflare can proxy the A record (it also removes the usual "no CNAME at
the apex" limitation via CNAME flattening). Three things to get right:

- **SSL/TLS mode must be Full or Full (strict).** `production.rb` sets
  `force_ssl`, so "Flexible" — where Cloudflare talks plain HTTP to the
  origin — redirects forever. It looks like the site hanging, not an error.
- **Deploy once DNS-only (grey cloud) first**, so Let's Encrypt can answer
  its own challenge and Kamal gets a certificate. Turn proxying on after.
- **Watch the webhook.** Postmark's POST is an automated request from a
  machine, and Cloudflare's bot or WAF rules can block it. The only symptom
  is newsletters silently not arriving, so if Postmark's Activity view shows
  failures the app never logged, add a skip rule for
  `/rails/action_mailbox/`.

MX records cannot be proxied — Cloudflare only proxies A, AAAA and CNAME —
so inbound mail bypasses all of this.

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

Generate `PASSWORD` as a long random string. It becomes
`RAILS_INBOUND_EMAIL_PASSWORD` in step 4.

## 3. Credentials

This repository carries no `config/credentials.yml.enc`. Generate your own,
once, on the machine you deploy from:

```bash
bin/rails credentials:edit
```

That writes `config/master.key`, which `.kamal/secrets` reads as
`RAILS_MASTER_KEY`. Never commit it.

## 4. config/deploy.yml

Already filled in: the host, `cjgilbert/newsbox` on Docker Hub, `siftbox.co`
as `proxy.host`, and the four `NEWSBOX_*` variables. `NEWSBOX_MAIL_FROM` is
the one to check against reality — it has to match the sender signature you
verified in step 2, or every password reset is rejected.

`service: newsbox` and the volume `newsbox_storage` are what keep this app
apart from the others on the box, so leave both alone unless something else
there already claims those names.

Secrets come from your shell via `.kamal/secrets`, so export them before
deploying (or wire the file up to a password manager):

```bash
export KAMAL_REGISTRY_PASSWORD=...
export RAILS_INBOUND_EMAIL_PASSWORD=...   # the PASSWORD from step 2
export POSTMARK_SMTP_TOKEN=...
```

`proxy.ssl: true` is already set, so Kamal gets a Let's Encrypt certificate
for `proxy.host` on the first deploy. That is also why step 1 comes first —
the certificate cannot be issued before the A record resolves.

Nothing to change for storage or the queue: the volume
`newsbox_storage:/rails/storage` is already declared, and
`SOLID_QUEUE_IN_PUMA: true` runs the worker inside Puma, which is what
fetches newsletter images.

## 5. First deploy

```bash
bin/kamal setup
```

The container entrypoint runs `db:prepare` when it starts the server, so the
four SQLite databases are created on the volume without a separate step.

## 6. Create the reader account

`db:prepare` loads `db/seeds.rb`, which creates nothing unless it is given an
email and password — so the first boot logs `No reader account created` and
carries on. Create the account after the deploy, rather than putting a
password in `deploy.yml`:

```bash
bin/kamal app exec "env NEWSBOX_EMAIL=you@example.com NEWSBOX_PASSWORD='...' bin/rails db:seed"
```

There is no sign-up flow, by design. This is the only account.

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

## 8. Smoke test

1. Sign in at `https://siftbox.co`.
2. Subscribe to something with the address in the feed header, or forward a
   real newsletter to it.
3. Open it and confirm the images have `src="/newsletters/…/images/…"` rather
   than the sender's CDN. That is the whole feature working end to end:
   webhook accepted, mailbox routed, job ran, images fetched and rewritten.
4. Check "View original" renders too — it is the sandboxed frame, and it
   embeds images as data URIs rather than fetching them.

The ingress is armed in production only, so the webhook endpoint answers 404
in development by design. Locally, use the conductor at
`/rails/conductor/action_mailbox/inbound_emails` instead — see `README.md`.

## Backups

Everything is one path. The four SQLite databases and every stored image sit
under `storage/` on the `newsbox_storage` volume, so backing that up backs up
the whole app, and nothing outside it needs backing up at all.

Worth knowing that it now grows: self-hosting images means a heavily
illustrated newsletter costs real disk, bounded per newsletter by
`Newsletter::RemoteImages::MAX_IMAGES` and
`Newsletter::ImageDownload::MAX_BYTES`.

## Still open

- `Feed` is not scoped to a user. With one account the authentication gate is
  the scope; see the note at the end of `README.md` for what multiple readers
  would take.
- A failed image fetch is not retried, so an image whose host was briefly
  unreachable at ingest stays hotlinked.
