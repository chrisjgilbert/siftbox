# Plan: making siftbox open source

## What we're building

siftbox is a private repository that runs one instance, at siftbox.co, for
one reader. This plan turns it into a public repository that anyone can clone
and run, with the same instance still running at siftbox.co behind a landing
page that tells visitors about both paths: join the waitlist for an address
here, or run your own.

The reasoning is in `docs/open-source.md`. That document found one blocker
(a Honeybadger key committed in plain text), three deployment details that
should leave the committed config, and a landing page that describes the
product as it was a month ago and speaks in the owner's voice. This document
is the work, cut into packages a fresh agent can pick up one at a time.

Nine packages. Three can start today in parallel. Two of them, the
Honeybadger key and the licence, are all that has to land before the
repository is made public; the rest can follow in public at the cost of
early visitors seeing a runbook where a README should be.

## What's already decided

From `docs/open-source.md`, and not reopened here:

- **MIT licence.** The app is a single-reader tool people run for
  themselves. There is no hosted product to protect.
- **The Honeybadger key is rotated, not scrubbed from history.** A rewrite
  would change every commit hash after `a5b6556` and break the links in
  every merged pull request.
- **Secrets come from the environment.** The encrypted credentials file
  goes. Nobody needs the master key to run or deploy the app.
- **The landing page is a switch**, off by default. A self-hoster's `/` is
  the sign-in page. siftbox.co turns it on.
- **The single reader stays.** The commit history stays. The design and
  planning documents in `docs/` stay.

Decided in this plan, because the landing page work needed decisions the
exploration did not make:

- **The waitlist stays.** It is how the owner learns whether anyone wants a
  hosted address, and the copy already promises one message and nothing
  else. The page gains a second path beside it, not instead of it.
- **The page describes the app as it is now.** The app opens on a daily
  edition written from newsletters and blogs. The page still says "Your
  news feed", which was true in August.
- **The product shot becomes an edition.** The shot is fixed sample markup
  and it shows the feed. Once the copy is about editions, a feed under it
  contradicts the copy.
- **Copy in this document is a draft in the owner's voice.** It is here so
  an agent has something concrete to build against. The owner edits it in
  the pull request before merge, and the agent should expect that.

## Vocabulary

| Term | Meaning here |
|---|---|
| Package | One branch, one pull request, one deploy. Named by a letter below. |
| Owner step | Something only the repository owner can do: a dashboard, a key, a file on the deploy machine, a GitHub setting. Listed per package and again at the end. |
| Self-hoster | Someone who clones the repository to run their own siftbox. |
| The switch | `SIFTBOX_WAITLIST`. On, `/` is the landing page and the waitlist accepts signups. Off, `/` sends a signed-out visitor to sign in. |
| Destination file | `config/deploy.production.yml`, which Kamal merges over `config/deploy.yml` when given `-d production`. Gitignored. Holds the values that name one deployment. |
| Rails credentials | `config/credentials.yml.enc`, decrypted with `config/master.key`. Being removed by package A. |
| Kamal secrets | `.kamal/secrets-common`, gitignored, read at deploy time and passed into the container as environment variables. |

## Ground rules for every package

- **Write the test first.** `.claude/rules/testing.md`. No `let`, no
  `before`, four phases, `build_stubbed` unless persistence is needed.
- **`bin/ci` has to pass**: tests, RuboCop, Brakeman, bundler-audit.
- **Match the surrounding code.** Read the files you will touch before
  changing them, and read the comments in them: this codebase explains its
  decisions inline, and a change that contradicts a comment without updating
  it is wrong twice.
- **Breaking a rule is fine with a reason in the diff.** Two packages below
  do, and say why.
- **Style-only changes go in their own commit.** Behaviour changes in
  another.
- **Commit messages** are an imperative subject and a prose body that says
  what changed and why. Read `git log` for the register.
- **The pull request description** leads with what the change does and what
  it costs, in prose. It names any owner step the deploy needs.
- **Only touch the files the package owns.** The file lists below are what
  keeps packages from conflicting when they run in parallel. If a package
  needs a file another package owns, say so in the pull request rather than
  editing it.
- **Do not change the visual system.** `docs/siftbox-redesign.md` §2 sets
  it: two typefaces, where Archivo is never uppercase and JetBrains Mono
  always is, uppercased in CSS rather than in the locale file; two rule
  weights, 2px ink and 1px rule, and nothing between; no radius and no
  shadow anywhere; one breakpoint at 720px. Spacing is per element and not
  tokenised.
- **No user-facing string in a template.** Everything goes through
  `config/locales/en.yml`, keys sorted alphabetically. A missing translation
  raises in development and test.

## Handing a package to an agent

Each package below is written to be read on its own. The brief for a fresh
agent is:

> Read `docs/open-source-plan.md` and do package X. Read
> `docs/open-source.md` first for why. Work on a branch named for the
> package, open a pull request against `main`, and stop there. Do not merge,
> do not deploy, and do not carry out owner steps.

Give the agent the letter and nothing else. If the package's "Owner steps"
section has a step that has to happen before the code can be written (there
is one, in A0), do it first and say so in the brief.

## The packages and their order

| Package | What | Depends on | Blocks going public? |
|---|---|---|---|
| A0 | Honeybadger key out of the repository | owner step: rotate the key | **Yes** |
| E | Licence, `SECURITY.md`, `CONTRIBUTING.md`, Dependabot cadence | nothing | **Yes** (the licence) |
| C1 | The landing page becomes a switch | nothing | No |
| A | Secrets from the environment; credentials file removed | A0 | No |
| B | Deploy config becomes a template; values move to a destination file | A, C1 | No. Optional; owner decides |
| C2 | Landing page: the copy and the second path | C1 | No. Deploy at or after the visibility change |
| C3 | Landing page: the product shot becomes an edition | C1 | No |
| F | A sample edition, and a screenshot | nothing | No |
| D | README and docs | A, B, C1, E, F | No, but first impressions |

A0, E, C1 and F can start at once, in parallel. C2 and C3 can run in
parallel with each other once C1 has merged. D is last.

## Package A0 — Honeybadger key out of the repository

**Why.** `config/honeybadger.yml:4` holds a live project key. It has been in
every commit since `a5b6556`, so once the repository is public it is
readable from history whatever the working tree says. Rotation makes the
old value worthless. This package moves the new one somewhere not committed.

**Owner step, before the code.** In the Honeybadger dashboard, create a new
project API key. Do not revoke the old one yet: production is still using
it. Put the new one in `.kamal/secrets-common` on the deploy machine as
`HONEYBADGER_API_KEY=...`.

**Read first.** `config/honeybadger.yml`, `config/deploy.yml` (the
`env.secret` block and its comments), `.kamal/secrets`, the deploy section
of `README.md`.

**Files you own.** `config/honeybadger.yml`, `config/deploy.yml` (only the
`env.secret` list), `.kamal/secrets` (comments only), `docs/deploying.md`
(step 4's list of secrets), `README.md` (the paragraph naming
`.kamal/secrets-common`).

**Build.**

- Delete the `api_key` line from `config/honeybadger.yml`. The gem maps
  every `HONEYBADGER_*` environment variable onto its configuration
  (`Honeybadger::Config::Env`), so with the line gone it reads
  `HONEYBADGER_API_KEY`. With neither set, the gem logs "API key is missing"
  per report and reports nothing; it does not stop the app booting. That is
  the behaviour a self-hoster gets, and it is the right one.
- Add `HONEYBADGER_API_KEY` to `env.secret` in `config/deploy.yml`, with a
  comment in the register of the ones already there: what reads it, what
  happens without it.
- Add the variable to the list in `docs/deploying.md` step 4 and the README
  paragraph that names what goes in `.kamal/secrets-common`.

**Tests first.** None. This is configuration, and a spec that reads the YAML
to assert a key is absent would be a spec of the file rather than of
behaviour. Say so in the pull request: this is the reason for breaking the
rule.

**Done when.** `bin/ci` is green; the deployed app, with the new key in
`.kamal/secrets-common`, still reports an error to Honeybadger (raise one
from a console: `bin/kamal console`, then `Honeybadger.notify("rotation
check")`). Then the owner revokes the old key.

**Do not.** Rewrite history. Touch any other file.

**Cost.** One more variable in the list of things that fail quietly.

## Package E — Licence and the two repository files

**Why.** Without a licence file a public repository is all rights reserved,
and nobody has permission to run the app. `SECURITY.md` gives a security
report somewhere to go other than a public issue, which matters for an app
that fetches URLs chosen by anyone who can email it. `CONTRIBUTING.md`
tells a stranger that the rules in `.claude/rules/` apply to them. The
Dependabot cadence is a public-facing detail: daily pull requests for two
ecosystems make the pull request list read as bot traffic.

**Read first.** `CLAUDE.md`, `.claude/rules/`, `.github/dependabot.yml`,
the "Outbound network" section of `README.md`.

**Files you own.** `LICENSE` (new), `SECURITY.md` (new),
`CONTRIBUTING.md` (new), `.github/dependabot.yml`.

**Build.**

- `LICENSE`: the MIT text verbatim, copyright line "Copyright (c) 2026
  Chris Gilbert".
- `SECURITY.md`, under thirty lines. Where to report (an email address the
  owner supplies in the pull request; leave a marked placeholder and say so
  in the description). What is in scope: the app fetches remote images and
  feeds from URLs written by strangers, and renders their HTML, so anything
  that reaches a private address through `Download::Destination`, or any
  script that runs on a page, is in scope. What to expect: a reply within a
  stated number of days, which the owner sets.
- `CONTRIBUTING.md`, about ten lines. Read `CLAUDE.md` and
  `.claude/rules/`. Write the test first. Run `bin/ci` before pushing.
  Style-only changes in their own commit. Expect the pull request
  description to say what the change costs.
- `.github/dependabot.yml`: weekly rather than daily, and group minor and
  patch updates for the bundler ecosystem into one pull request. Keep the
  ten-request limit.

**Tests first.** None; documents and a YAML file.

**Done when.** The four files exist, GitHub's licence detection reads
`LICENSE` as MIT (check the repository page once merged), and Dependabot's
next run opens grouped pull requests.

**Do not.** Add a code of conduct, an issue template or a pull request
template. Nothing asked for them.

**Cost.** Grouped Dependabot updates are harder to bisect when one breaks
CI.

## Package C1 — The landing page becomes a switch

**Why.** `/` serves a signed-out visitor a landing page that collects
waitlist signups for siftbox.co and speaks as the owner. A self-hoster's
instance would show it to their visitors and collect signups for nothing.
This package makes the landing page and the waitlist something a deployment
turns on, with off as the default.

**Read first.** `config/application.rb` (how `SIFTBOX_INBOUND_ADDRESS`
becomes `config.x.inbound_address`),
`app/controllers/waitlist_signups_controller.rb`,
`app/controllers/concerns/authentication.rb`, `config/routes.rb`,
`spec/requests/waitlist_signups_spec.rb`, `spec/support/authentication_helper.rb`,
`.claude/rules/controllers.md`.

**Files you own.** `config/application.rb`,
`app/controllers/waitlist_signups_controller.rb`,
`spec/requests/waitlist_signups_spec.rb`, `spec/support/waitlist_helper.rb`
(new), `config/deploy.yml` (only to add `SIFTBOX_WAITLIST` to `env.clear`,
with a comment), `README.md` (one row in the table of variables that fail
quietly), `docs/deploying.md` (step 4, one line).

**Build.**

- `config/application.rb`: `config.x.waitlist`, from
  `ENV.fetch("SIFTBOX_WAITLIST", "false") == "true"`, with a comment in the
  register of the one above it: what it decides, and that off is the
  self-hoster's default.
- `WaitlistSignupsController#new`: a signed-in reader is redirected as
  today. A signed-out visitor with the switch off is redirected to
  `new_session_url`. With it on, the landing page renders as today.
- `WaitlistSignupsController#create`: with the switch off, answer 404
  (`head :not_found`) before the rate limiter and before anything is read
  from `params`. A `before_action` is the shape; it is HTTP, which is what
  a controller is for. With it on, unchanged.
- The routes do not change. `root "waitlist_signups#new"` stays, because
  that action is where the signed-in redirect lives.
- A private predicate on the controller reads
  `Rails.configuration.x.waitlist`. Nothing else in the app reads the
  switch. (The masthead and every page behind the gate are unaffected: a
  signed-in reader never sees the landing page whatever the switch says.)

**Tests first.**

- `spec/support/waitlist_helper.rb`, in the shape of
  `spec/support/authentication_helper.rb`: a module with two methods,
  `open_the_waitlist` and `close_the_waitlist`, included for `:request` and
  `:system` examples. Each stubs the configuration:
  `allow(Rails.configuration.x).to receive(:waitlist).and_return(true)` or
  `false`. The custom configuration object answers `respond_to?` for any
  name, so this passes `verify_partial_doubles`. C2 and C3 use the same
  helper from their system specs.
- In `spec/requests/waitlist_signups_spec.rb`, every existing example that
  reaches the landing page or posts a signup calls `open_the_waitlist` in
  its setup phase. The three signed-in redirect examples do not need it.
- New examples, each one path, each calling `close_the_waitlist` in setup
  rather than relying on the default (the test environment sets no
  `SIFTBOX_WAITLIST`, so the default is off today, and a later CI variable
  must not change what these examples test):
  - "sends a signed-out visitor to sign in while the waitlist is closed"
  - "answers 404 to a signup while the waitlist is closed"
  - "records nothing for a signup while the waitlist is closed"
  - "keeps sending a signed-in reader to the edition while the waitlist is
    closed"

**Done when.** `bin/ci` is green. In development with the variable unset,
`/` redirects to `/session/new`; with `SIFTBOX_WAITLIST=true bin/dev`, the
landing page renders and a signup works. Both checked by hand and said so in
the pull request.

**Do not.** Change any copy or markup; that is C2. Change the routes. Read
`ENV` anywhere but `config/application.rb`.

**Owner step, at deploy.** `SIFTBOX_WAITLIST: "true"` in `env.clear` (in
`config/deploy.yml` until B lands, in the destination file after). Without
it siftbox.co's landing page disappears on deploy.

**Cost.** One more variable that fails quietly, and a landing page that no
longer appears in a fresh development environment unless asked for. The
README row says both.

## Package A — Secrets from the environment

**Why.** Three values live in `config/credentials.yml.enc`, which only the
master key opens: the reader account, the Action Mailbox ingress password,
the Postmark send token. A self-hoster cannot use the committed file and
nothing tells them to delete it. The app already reads its Anthropic key
from the environment, which is what Kamal's `env.secret` exists for. After
this package, everything does, the credentials file is gone, and the master
key is needed by nobody.

**Read first.** `db/seeds.rb` and `spec/db/seeds_spec.rb`,
`config/environments/production.rb` (the mailer block at the end),
`spec/requests/action_mailbox_ingress_spec.rb` (the `stub_ingress_password`
helper and its comment), `config/deploy.yml` (`env.secret`),
`.kamal/secrets`, `.gitignore` (the credentials block and its comment),
`.claude/hooks/session-start.sh` (its last comment), `Dockerfile` (the
`assets:precompile` line), and the "Receiving mail" and "Deploying"
sections of `README.md` and steps 3 and 6 of `docs/deploying.md`.

Also read, in the bundle rather than the repository:
`actionmailbox/app/controllers/action_mailbox/base_controller.rb` line 31,
which reads the credential first and `RAILS_INBOUND_EMAIL_PASSWORD` second,
per request; and `railties/lib/rails/application/configuration.rb`
`secret_key_base`, which reads `SECRET_KEY_BASE` from the environment
before it reads credentials.

**Files you own.** `db/seeds.rb`, `spec/db/seeds_spec.rb`,
`config/environments/production.rb`,
`spec/requests/action_mailbox_ingress_spec.rb`, `config/credentials.yml.enc`
(deleted), `config/deploy.yml` (`env.secret` only), `.kamal/secrets`,
`.gitignore`, `.claude/hooks/session-start.sh` (the comment),
`docs/deploying.md` (steps 3 and 6), `README.md` (the two sections named
above, minimally: package D rewrites it).

**Build.**

| Value | Today | After |
|---|---|---|
| Ingress password | `credentials.action_mailbox.ingress_password` | `RAILS_INBOUND_EMAIL_PASSWORD`. No code change: Action Mailbox falls back to it when the credential is absent, and after this package the credential is always absent. |
| Postmark send token | `credentials.dig(:postmark, :smtp_token)` in `production.rb` | `ENV.fetch("POSTMARK_SMTP_TOKEN", nil)`. With a default, against `.claude/rules/ruby.md`, because the Dockerfile boots the production environment to precompile assets with no secrets present, and a `fetch` without a default fails the image build. Say this in a comment on the line. |
| Reader account | `credentials.reader` in `db/seeds.rb` | `SIFTBOX_READER_EMAIL` and `SIFTBOX_READER_PASSWORD`. Same guard as today: both absent or either blank logs "No reader account created" and continues, because seeds run at first container boot, before anything is reachable. Same create-never-update rule, for the reason in the file's comment. |
| `secret_key_base` | Derived from the credentials file | `SECRET_KEY_BASE`. Rails reads it from the environment first. Nothing in the repository changes for this; it is an owner step. |

Then:

- Delete `config/credentials.yml.enc`.
- `config/deploy.yml` `env.secret`: remove `RAILS_MASTER_KEY`; add
  `SECRET_KEY_BASE`, `RAILS_INBOUND_EMAIL_PASSWORD`, `POSTMARK_SMTP_TOKEN`,
  `SIFTBOX_READER_EMAIL`, `SIFTBOX_READER_PASSWORD`. Each with a comment in
  the register of the existing ones. The reader's address is not a secret,
  but it is the owner's, and `env.secret` keeps it out of the committed
  file.
- `.kamal/secrets`: remove the `RAILS_MASTER_KEY=$(cat config/master.key)`
  line. Rewrite the comments so the file says what it now is: a list of the
  variable names a deployment needs, whose values go in
  `.kamal/secrets-common`.
- `.gitignore`: remove the four-line credentials block and its comment.
  They ignore files that no longer have a reason to exist.
- `.claude/hooks/session-start.sh`: the closing comment says seeds read
  encrypted credentials. They read the environment now; two variables the
  container does not set, so the behaviour (test database only) is the same
  and the comment changes.
- `spec/requests/action_mailbox_ingress_spec.rb`: `stub_ingress_password`
  stubs the credential. Its comment says stubbing the fallback would
  "authenticate nothing in production". After this package the fallback is
  the only mechanism, so the helper stubs
  `ENV["RAILS_INBOUND_EMAIL_PASSWORD"]` instead (Action Mailbox reads it per
  request, so a stub on `ENV` in the example is enough) and the comment is
  rewritten to say why that is now right.
- `docs/deploying.md` step 3 becomes "Secrets": the list of variables, where
  they go, and that `config/master.key` is no longer part of a deploy. Step
  6 reads the reader account from the two variables.
- `README.md`: the "Receiving mail" paragraphs about credentials versus the
  environment variable go, replaced by one sentence. The "Deploying" table
  gains the new variables and loses `RAILS_MASTER_KEY`.

**Tests first.**

- `spec/db/seeds_spec.rb`: the six examples keep their names and their
  assertions; `stub_reader` sets the two environment variables instead of
  stubbing credentials. `stub_const("ENV", ENV.to_h.merge(...))` is the
  house-compatible way; it is a stub, and the seeds file reads through
  `ENV.fetch` with a default or `ENV[]`, both of which a Hash answers.
- `spec/requests/action_mailbox_ingress_spec.rb`: the four examples keep
  their names; only the helper changes.

**Done when.** `bin/ci` is green. `git grep credentials` finds nothing in
`app/`, `config/`, `db/`, `spec/` or `bin/` except in prose and in the
commented-out Rails defaults of `config/storage.yml`. A fresh clone with no
master key runs `bin/setup` and `bin/rspec` without touching credentials
(the session-start hook already proves the second half).

**Do not.** Generate a new `secret_key_base` in the repository or in docs
as a fait accompli; the owner decides (below). Change how seeds decide
whether to update an account.

**Owner steps, at deploy, all in the same release as the code.** On the
machine that holds `config/master.key`, before merging:

1. `bin/rails credentials:show` and copy out four values: the reader's
   email and password, `action_mailbox.ingress_password`,
   `postmark.smtp_token`, and `secret_key_base`.
2. Write them into `.kamal/secrets-common` under the new names. Carry the
   existing `secret_key_base` across rather than generating a new one: a
   new one signs the reader out once and voids any password-reset link in
   flight. Nothing else depends on it; stored image paths use plain blob
   ids, checked in `app/models/newsletter.rb` `inline_image_path`. Carrying
   it over costs nothing and avoids the sign-out.
3. Deploy. Run the smoke test in `docs/deploying.md` step 8 in full:
   inbound mail and password reset both changed how they are configured.
4. Delete `config/master.key` from the deploy machine once the smoke test
   passes. Keep a copy of the old credentials somewhere private for a week
   in case a value was mis-copied.

**Cost.** Four files and a release that has to carry every value across at
once, or inbound mail and password reset stop. The README's argument about
credentials, which is some of its best writing, is replaced by a table.

## Package B — Deploy config becomes a template

**Optional.** `docs/open-source.md` recommends this and says leaving the
address in is defensible. The owner decides; if the decision is to leave
it, skip this package and have D describe `config/deploy.yml` as the one
file to edit.

**Why.** `config/deploy.yml` names the production host at lines 22 and
146, the Docker Hub username at lines 9 and 59, `siftbox.co` as the proxy
host, and the four `SIFTBOX_*` values. `docs/deploying.md` repeats the
address. The host is shared with the owner's other apps, so the address
identifies more than siftbox, and history is permanent. Kamal has a native
mechanism for this: a destination file merged over the base config.

**Read first.** `config/deploy.yml` in full, `docs/deploying.md` in full,
`.kamal/secrets`, `.gitignore`, `.dockerignore` (which already excludes
`config/deploy*.yml`). In the bundle: `kamal/lib/kamal/configuration.rb`
`load_raw_config` (the destination file is deep-merged over the base, so a
hash in both merges and an array in both is replaced) and
`kamal/lib/kamal/secrets.rb` `secrets_filenames` (with a destination, Kamal
reads `.kamal/secrets-common` and `.kamal/secrets.production`, and does
**not** read `.kamal/secrets`). Also `kamal/lib/kamal/configuration/role.rb`
`container_prefix`: with a destination, containers and the kamal-proxy
service are named `siftbox-web-production` rather than `siftbox-web`.

**Files you own.** `config/deploy.yml`, `.gitignore`, `.kamal/secrets`,
`docs/deploying.md`, `README.md` (the deploy section, minimally).

**Build.**

- `config/deploy.yml` keeps everything that is true of every deployment:
  `service`, the volume, the proxy block minus `host`, the health check,
  `env.clear` with `SOLID_QUEUE_IN_PUMA`, `env.secret`, the aliases,
  `asset_path`, `builder.arch`. Everything that names one deployment gets a
  placeholder that cannot be mistaken for a value: `image:
  your-registry-user/siftbox`, `hosts: - your-host.example.com`,
  `proxy.host: siftbox.example.com`, `registry.username`, the `SIFTBOX_*`
  values with `example.com` addresses. `builder.remote` goes: it is the
  owner's arm64 workaround and belongs in the destination file. Keep the
  comments; they are the runbook's reasoning.
- `.gitignore`: `/config/deploy.*.yml` and `/.kamal/secrets.*`, each with a
  one-line comment.
- `.kamal/secrets` becomes the self-hoster's file: for a deploy with no
  destination it is what Kamal reads, so it lists the variable names with
  comments and no values. Say in it that a destination deploy reads
  `.kamal/secrets.production` instead, and that the owner keeps values in
  `secrets-common` which both paths read.
- `docs/deploying.md`: the address in the DNS table becomes
  `<the host's address>`; step 4 describes the destination file and shows
  its full content with placeholders; every `bin/kamal` command in the
  document gains `-d production` where the owner runs it, with a sentence
  saying a self-hoster editing `config/deploy.yml` directly omits it.
- A new subsection in `docs/deploying.md`, "Moving a running deployment
  onto a destination", with the cutover below.

**The cutover, which is an owner step and the risk in this package.** The
first `-d production` deploy names its containers and its proxy service
differently from the ones running. Whether kamal-proxy accepts a second
service claiming `siftbox.co` while the first still holds it was not
verified. The safe sequence is: `bin/kamal app remove` for the old,
destination-less deployment (the named volume `siftbox_storage` survives;
`app remove` removes containers, not volumes, but confirm in Kamal's source
before running it), then `bin/kamal deploy -d production`. Expect a minute
or two of downtime. Postmark retries inbound mail for hours, so nothing is
lost; a reader mid-page sees an error. Do it at a quiet hour and check the
volume is attached afterwards (`bin/kamal app exec -d production --reuse
"ls storage"`).

**Owner step, before the cutover.** Create `config/deploy.production.yml`
on the deploy machine with the values from today's `config/deploy.yml`:
`image`, `servers.web.hosts`, `proxy.host`, `registry.username`, the four
`SIFTBOX_*` values plus `SIFTBOX_WAITLIST: "true"` from C1, and
`builder.remote`. The pull request description shows this file with
placeholders so it can be copied.

**Tests first.** None. Kamal config is not under test. Say so.

**Done when.** `bin/kamal config -d production` on the deploy machine prints
the merged config with the real host, and `bin/kamal config` with no
destination prints placeholders and fails nowhere. The cutover has run and
the smoke test in step 8 passes.

**Do not.** Introduce an ERB-and-local-YAML scheme in `config/deploy.yml`
instead. It would avoid the cutover, but it is a home-made mechanism in a
file readers expect to be plain Kamal, and the cutover is one-off. If the
owner prefers no cutover, that is the alternative, and it is a different
package.

**Cost.** The runbook loses its worked example. Production's truth splits
between a committed template and a file that exists only on the deploy
machine. One cutover with downtime. The address already in history stays
there.

## Package C2 — Landing page: the copy and the second path

**Why.** The page says "Your news feed" and describes a feed; the app opens
on a daily edition. The closing band offers one path, an address here. Once
the code is public there are two: an address here, or run your own. And the
footer says "A side project", which is still true but is no longer the most
useful thing to say there.

**Read first.** `docs/siftbox-redesign.md` §2 and §9,
`app/views/waitlist_signups/_landing.html.erb`, `_form.html.erb`,
`_joined.html.erb`, `new.html.erb`, `create.html.erb`,
`create.turbo_stream.erb`, the `waitlist_signups` block of
`config/locales/en.yml`, the landing, waitlist, points and closing blocks of
`app/assets/stylesheets/application.css` (from the `Landing page` comment at
line 1584 to the `Product shot` comment at 2009),
`spec/requests/waitlist_signups_spec.rb` line 13 (the one assertion on
copy), `spec/system/editions_spec.rb` (the shape of a system spec here),
`.claude/rules/views.md`.

**Files you own.** `app/views/waitlist_signups/_landing.html.erb`,
`config/locales/en.yml` (every `waitlist_signups` key except `shot`, which
C3 owns), `app/assets/stylesheets/application.css` (the landing, points
and closing blocks only; not the shot block), `config/application.rb` (one
line: `config.x.source_url`), `app/helpers/application_helper.rb` (one
helper, `source_url`, in the register of `inbound_address`),
`spec/requests/waitlist_signups_spec.rb` (line 13 only),
`spec/system/landing_spec.rb` (new).

**Build.** The page keeps its bones: nav, hero, shot, two points, closing
band, footer. What changes in each:

*Nav.* Two links on the right instead of one: "Source" to the repository,
then "Join the waitlist" as today. The nav is a flex row with
`space-between`; the two links go in a small flex group with a 24px gap
and the same `landing__nav-link` treatment, arrow and all.

*Hero.* Eyebrow, title, standfirst and the form's note change. The form does
not.

| Key | Today | Draft |
|---|---|---|
| `new.eyebrow` | Early access | Open source · Early access |
| `new.title` | Your news feed | Your morning edition |
| `new.page_title` | siftbox — your news feed | siftbox — your morning edition |
| `new.standfirst` | Siftbox gives your subscriptions a dedicated address and collects everything that arrives into one feed. Newest first, grouped by day, stripped of the styling that makes newsletters hard to read. | Siftbox gives your subscriptions a dedicated address and reads everything that arrives, newsletters and blogs alike, into one edition each morning: what the stories were, who covered them, and where they disagree. Every line links to the original. |
| `form.note` | One message when it opens. Nothing else. | One message when the hosted version opens. Nothing else. |
| `joined.note` | You'll get one message when siftbox opens. | You'll get one message when the hosted version opens. |

*Points.* Still two. The first is still true. The second was about the
feed.

| Key | Today | Draft |
|---|---|---|
| `points.feed.kicker` | 02 / A feed, not a mailbox | 02 / An edition, not an inbox |
| `points.feed.title` | Read what you want, when you want | Read the morning, not the mail |
| `points.feed.body` | Newest first, grouped by day. Nothing accumulates into a number you have to clear, and nothing gets buried under a receipt. | An editor reads everything that arrived overnight and writes the stories up, with the sources under each one. The originals stay in the archive for when you want the whole thing. |

Rename the locale key from `feed` to `edition` and the loop in the template
with it.

*Closing band.* Today: a title and body on the left, the inverted form on
the right, one grid row. After: two rows in the same grid. Row one is the
waitlist as today, with the body rewritten. Row two is the second path: a
title, a body, and a link in place of a form. Between the rows, a 1px rule
in paper at reduced opacity is the only new visual element, and it is the
system's thin rule on the system's dark surface.

| Key | Draft |
|---|---|
| `closing.address.title` | Want an address? |
| `closing.address.body` | siftbox.co is one person's instance for now. The waitlist tells me whether to open it up, and you get one message if it does. |
| `closing.source.title` | Or run your own |
| `closing.source.body` | The whole app is open source under the MIT licence: one Rails app, one container, one SQLite file on one volume. Point a Postmark inbound stream at it and you have an address by the evening. |
| `closing.source.link` | Read the source |

The link is the `landing__nav-link` treatment in paper, arrow included, and
opens in the same tab: it is a link, not an app action, and nothing on this
page opens new tabs.

*Footer.* "A side project · built on Rails and Action Mailbox" becomes
"Open source · MIT · built on Rails and Action Mailbox", with "Open source"
linking to the repository. Same mono treatment.

*The repository address.* `config.x.source_url =
"https://github.com/chrisjgilbert/siftbox"` in `config/application.rb`,
with a one-line comment, and a `source_url` helper beside
`inbound_address`. Not an environment variable: nothing needs to change it
per deployment, and a fork with the switch on pointing at the upstream
repository is accurate.

**Tests first.**

- `spec/requests/waitlist_signups_spec.rb` line 13 asserts "Your news feed".
  Change it to the new title.
- `spec/system/landing_spec.rb`, new, read by accessible name and role, no
  CSS selectors:
  - "offers the source to a visitor" — `have_link("Read the source",
    href: "https://github.com/chrisjgilbert/siftbox")`
  - "offers the source from the nav" — `have_link("Source", href: ...)`
  - "names both ways in" — has text "Want an address?" and "Or run your
    own"
  - "still takes a signup" — fill in the email field by its label, click
    "Join the waitlist", expect "On the list"
  Each calls `open_the_waitlist`, the helper C1 put in `spec/support/`, in
  its setup phase.

**Done when.** `bin/ci` is green. Screenshots at 375px and 1280px in the
pull request, taken with the `verify` skill's Playwright recipe against
`SIFTBOX_WAITLIST=true`, so the owner can read the copy in place. The owner
has edited the copy in the pull request, or said it stands.

**Do not.** Touch `_shot.html.erb`, the `shot` locale keys or the shot CSS;
C3 owns them and runs in parallel. Add a third point. Add a screenshot
image to the page; the shot is markup by design (§9.5 and the note in
`_shot.html.erb`). Open links in new tabs.

**Deploy note.** The source link 404s for the public until the repository
is public. Deploy this at or after the visibility change, or accept a dead
link for the interval.

**Cost.** One more surface with a rule on it, and a closing band twice as
tall on mobile.

## Package C3 — Landing page: the product shot becomes an edition

**Why.** The shot is fixed sample markup at the feed's row spec: a day
heading and five rows. After C2 the copy above it is about editions. The
shot should show one.

**Read first.** `app/views/waitlist_signups/_shot.html.erb` and its opening
comment, the `waitlist_signups.shot` block of `config/locales/en.yml`, the
`Product shot` block of `app/assets/stylesheets/application.css` (line 2009
to the end), and, for what an edition looks like at full size, the
`Edition` and `Story` blocks of the same file (from line 234) and
`app/views/editions/show.html.erb`, `_section.html.erb`,
`_story.html.erb`. `docs/siftbox-redesign.md` §2.

**Files you own.** `app/views/waitlist_signups/_shot.html.erb`,
`config/locales/en.yml` (the `waitlist_signups.shot` block only),
`app/assets/stylesheets/application.css` (the `Product shot` block only),
`spec/system/landing_spec.rb` (append examples; C2 creates the file, so if
C2 has not merged, create it and expect a small conflict).

**Build.** Same frame: the 1px ink border, the caption bar with its 2px
rule, the body padding, the 720px breakpoint. Inside it, the edition's
hierarchy at the shot's reduced scale:

- The masthead line as the caption bar's left text: "No. 31 · Thursday 18
  September". Right text: "Written at 07:00 from everything that arrived".
- Three section groups, each headed the way `shot__group` heads the day
  today (mono, uppercase in CSS, 2px rule): "Lead stories", "Briefly", "The
  reading list".
- Under each, stories at the shot's scale. A lead story: headline (Archivo
  600, 17px on mobile and 20px at the breakpoint, the current
  `shot__subject` scale), two lines of body (Archivo 400, 14px, `--body`),
  a sources line (mono, 10px, uppercase in CSS, `--mute`: "Sources / Ruby
  Weekly / This Week in Rails", slashes as the feed's mono lines draw
  them). A Briefly line: body only, then sources. A reading list entry:
  headline and sources.
- Fixed content, in the locale file, as the rows are today. Draft:

```yaml
shot:
  caption: No. 31 · Thursday 18 September
  subcaption: Written at 07:00 from everything that arrived
  sections:
    - heading: Lead stories
      stories:
        - headline: Ruby 3.5 preview ships with the new parser on by default
          body: Two newsletters carry the release and disagree on one point:
            whether the rewritten parser is faster in ordinary code or only
            on the benchmark the core team published. Both link the same
            changelog.
          sources: [ Ruby Weekly, This Week in Rails ]
    - heading: Briefly
      stories:
        - body: Postgres 18 beta 2 adds skip scan to multi-column indexes,
            which makes a query that skips the leading column use the index
            at all.
          sources: [ Postgres Weekly ]
        - body: A short argument for media that has no idea whether you
            finished it.
          sources: [ Offscreen ]
    - heading: The reading list
      stories:
        - headline: Consistent hashing, drawn out properly
          sources: [ The Whiteboard ]
```

  The senders are the ones `lib/tasks/sample_data.rake` and the current
  shot already use, real newsletters with invented headlines, plus one from
  the fabricated corpus. Keep the headlines plausible and not real: the
  page must not report news.
- Delete the row markup and the `shot__row`, `shot__row--read`,
  `shot__number`, `shot__time`, `shot__text`, `shot__sender`,
  `shot__subject` rules, and the `rows`, `day`, `date` locale keys. Leftover
  CSS for a removed feature is what `.claude/rules/review.md` says to look
  for.
- Rewrite the comment at the top of `_shot.html.erb` and the one above
  `.shot`: they say the feed's row spec, and it is the edition's now. Keep
  the sentence about why it is static.

**Tests first.** In `spec/system/landing_spec.rb`, each example calling
`open_the_waitlist` (C1's helper in `spec/support/`) in its setup phase:

- "shows an edition in the product shot" — has text "Lead stories" and the
  lead headline
- "keeps the shot's sources as text, not links" — `not_to have_link("Ruby
  Weekly")`; the shot is a picture made of markup, and a link into nothing
  would be a broken promise

**Done when.** `bin/ci` is green. Screenshots at 375px and 1280px in the
pull request. The shot reads as a smaller edition page: same hierarchy,
same rules, same two typefaces. Nothing in it is a link.

**Do not.** Reuse the `edition` and `story` classes inside the shot; they
are set at the reading measure and the shot is a reduced-scale picture.
Render the shot from the edition partials: they take presenters built from
records, and the landing page has no records. Change the frame.

**Cost.** Roughly sixty lines of CSS replacing forty, and content that will
go stale the next time the edition page's hierarchy changes. It is a
picture; pictures go stale.

## Package F — A sample edition, and a screenshot

**Why.** `sample_data:load` fills the development archive with newsletters
but composes no edition, so a fresh development environment opens on "No
editions yet". The README needs a screenshot of the edition page, and the
`verify` skill needs an edition to screenshot. Composing one needs an
Anthropic key and costs money, which a sample task must not.

**Read first.** `lib/tasks/sample_data.rake`, `app/models/edition.rb`,
`app/models/edition/story.rb`, `app/models/edition/citation.rb`,
`app/models/edition/editor.rb` (`record`, `build` and `cite`: how a
composed edition is written as one graph and one `save!`),
`spec/factories.rb`, `.claude/skills/verify/SKILL.md`.

**Files you own.** `lib/tasks/sample_data.rake`, `lib/sample_edition.rb`
(new), `spec/lib/sample_edition_spec.rb` (new), `docs/images/edition.png`
(new), `README.md` (nothing: D embeds the image).

**Build.**

- `SampleEdition`, a PORO in `lib/`, beside `EditionCorpus` in shape: given
  the newsletters the sample task created, it builds one edition with one
  lead story citing two of them, two Briefly lines citing one each, and one
  reading list entry, and saves the graph the way `Edition::Editor#record`
  does: attributes assigned, stories and citations built in memory, one
  `save!`. `editor_model` and `prompt_version` say "sample" so the row is
  never mistaken for a composed one. Number from `Edition.next_number`,
  `published_on` today, the window from the oldest newsletter's
  `received_at` to now.
- `sample_data:load` calls it after the newsletters, and the task's closing
  line reports the edition as well as the count. The task already destroys
  editions before newsletters, so it stays idempotent.
- The screenshot: run the task, sign in through the `verify` skill's
  recipe, screenshot `/` (which redirects to the edition) at 1280px wide,
  full page, and commit it as `docs/images/edition.png`. Under 300KB; use
  the PNG the skill's Playwright call produces and optimise it if it is
  larger. Take it with a real edition of sample data, never with the owner's
  own instance.

**Tests first.** `spec/lib/sample_edition_spec.rb`:

- "writes one edition citing every sample newsletter" — create four
  newsletters, build, expect `Edition.count` 1 and every newsletter cited
- "files a story in each section" — lead, briefly and reading list all
  present
- "marks the edition as a sample" — `editor_model` is "sample"

**Done when.** `bin/rails sample_data:load` in development produces an
archive and an edition, `/` opens on it, and the screenshot is in
`docs/images/`. `bin/ci` green.

**Do not.** Call the model. Add the sample edition to the test suite's
fixtures. Screenshot anything but sample data.

**Cost.** Another thing in `lib/` that mirrors composition and will need
updating when a section is added.

## Package D — README and docs

**Why.** The README is a runbook for one deployment, written for the person
who runs it. It is stale in three places, has no picture, and leads with
operations. For a reviewer it is the first screen; for a self-hoster it is
the only instructions. This package makes it an introduction and moves what
it holds now under `docs/`, where it is still needed.

**Depends on** A, B (or the decision to skip it), C1, E and F having merged.
Read their pull requests; this package describes the state they left.

**Read first.** `README.md` in full, `docs/deploying.md`,
`docs/open-source.md`, `CLAUDE.md`, `app/views/layouts/application.html.erb`
line 19, `docs/siftbox-redesign.md` line 3, `docs/blogs-rss-reply.md` lines
1 to 8, `.github/workflows/ci.yml` (for the badge).

**Files you own.** `README.md`, `docs/operating.md` (new),
`app/views/layouts/application.html.erb` (one comment),
`docs/siftbox-redesign.md` (one note at the top),
`docs/blogs-rss-reply.md` (one note at the top).

**Build.**

- `docs/operating.md` is today's README with its stale lines fixed: "Three
  screens" becomes a paragraph naming the edition, the originals archive,
  subscriptions, settings and blogs; the variables table reflects A, B and
  C1; the credentials paragraphs are gone (A did most of this). Keep every
  decision paragraph: sanitising at render, self-hosted images, the egress
  rule, the feed bound, the landing page's four guards, `noindex`. Keep
  "Deferred".
- `README.md`, new, about a hundred lines, in this order:
  1. One paragraph: what siftbox is. One address for your newsletters, blog
     feeds beside them, a daily edition written from everything that
     arrived, with every claim linked to its original. One reader. Runs in
     one container on one SQLite volume.
  2. The screenshot from F.
  3. A CI badge.
  4. How it works, five or six sentences: Action Mailbox and Postmark
     receive; sanitising at render; images fetched and self-hosted with
     the SSRF defence named; editions composed at 07:00 by a job; blogs
     polled hourly.
  5. Run it locally: export the two variables that give it a reader
     (`SIFTBOX_READER_EMAIL`, `SIFTBOX_READER_PASSWORD`), then `bin/setup`,
     whose `db:prepare` seeds the account from them; then
     `bin/rails sample_data:load` and `bin/dev`. `SIFTBOX_WAITLIST=true` as
     well if you want the landing page.
  6. What it needs from outside, one line each: a Postmark server for
     inbound mail and reset mail (required); an Anthropic key for editions
     (optional; without it the originals archive works and the editions
     page stays empty, say so plainly); Honeybadger (optional).
  7. Deploying: one paragraph pointing at `docs/deploying.md` and naming
     Kamal and the volume.
  8. How it is built: one sentence that the app was built with Claude Code,
     and that `CLAUDE.md` and `.claude/rules/` are how the author directs
     it. Link `docs/` for the design and planning documents.
  9. Support expectations, one sentence, the owner's to write.
  10. Licence.
- `app/views/layouts/application.html.erb` line 19: the comment says
  opening a newsletter marks it read. Read state was retired; the tag stays
  for the reason `docs/operating.md` gives (prefetch would pull large
  bodies on hover). Rewrite the comment to that.
- `docs/siftbox-redesign.md`: a one-line note under the title that
  `design_handoff_siftbox/README.md` was a design handoff kept outside the
  repository.
- `docs/blogs-rss-reply.md`: a one-line note under the title that this was
  a message to a parallel branch, that the branch and `docs/silencing.md`
  were not merged, and that it is kept as a record of the decision.

**Tests first.** None; documents and a comment.

**Done when.** A stranger reading the README knows what the app is, has
seen it, and can run it in five commands. `docs/operating.md` says nothing
that is no longer true. The badge is green.

**Do not.** Restate `docs/deploying.md` in the README. Promise support the
owner has not agreed to. Describe package B's destination file if B was
skipped.

**Cost.** Two documents where there was one, and a README that will drift
the next time a variable is added unless the pull request that adds it
touches the README too. `CONTRIBUTING.md` should say that.

## Owner steps, collected

In order. Each is named in the package it belongs to.

1. **A0, before the code.** New Honeybadger key; into
   `.kamal/secrets-common`. After A0 deploys and reports: revoke the old.
2. **E, in the pull request.** The security contact address and the reply
   window for `SECURITY.md`.
3. **C1, at deploy.** `SIFTBOX_WAITLIST: "true"` in `env.clear`.
4. **A, at deploy.** Copy five values out of credentials into
   `.kamal/secrets-common` under their new names; deploy; smoke test; delete
   the master key from the deploy machine.
5. **B, if doing it.** Create `config/deploy.production.yml`; run the
   cutover at a quiet hour.
6. **C2 and C3, in the pull request.** Edit the copy or say it stands.
7. **Going public**, once A0 has deployed and E has merged. In GitHub, in
   this order: description, website, topics; change the visibility; then
   the settings that appear only for a public repository: secret scanning
   and push protection, branch protection on `main` requiring the CI
   workflow.
8. **D, in the pull request.** The support sentence.

## Deploy steps

| Package | Step |
|---|---|
| A0 | `HONEYBADGER_API_KEY` in `.kamal/secrets-common` before deploying. Revoke the old key after. |
| C1 | `SIFTBOX_WAITLIST: "true"` in `env.clear` before deploying, or the landing page disappears. |
| A | Five values into `.kamal/secrets-common` before deploying. Smoke test after. Not a rolling change: a container booted without them has no reader account and rejects every webhook. |
| B | The destination file first, then the cutover, with downtime. |
| C2 | At or after the visibility change, or the source link is dead. |
| E, C3, F, D | Nothing. |

## The things most likely to go wrong

1. **Package A's release.** Every value has to be in `secrets-common`
   before the deploy, under the exact new name. A typo in
   `RAILS_INBOUND_EMAIL_PASSWORD` is a 401 on every webhook with nothing in
   the log to say why, which is the failure the README used to spend three
   paragraphs on. The smoke test is not optional.
2. **The `fetch` default in `production.rb`.** An agent following
   `.claude/rules/ruby.md` will write `ENV.fetch("POSTMARK_SMTP_TOKEN")` and
   break the image build at `assets:precompile`, in CI or on the deploy
   machine, not in the suite. The reason for the default has to be on the
   line.
3. **Package B's cutover.** Whether kamal-proxy lets a differently named
   service claim a host that another still holds was not verified. Do the
   `app remove` first, at a quiet hour, and confirm the volume before
   declaring it done.
4. **C2 and C3 in parallel.** They own different keys in the same locale
   file and different blocks of the same stylesheet. Git will merge that;
   the second to land rebases. What Git will not catch is one of them
   changing a class name the other relies on, so neither should.
5. **The switch's default under test.** The switch is read once at boot,
   so a spec cannot flip it by setting the variable; it stubs the
   configuration. C1's helper does that for both states. An example that
   asserts the closed behaviour without calling `close_the_waitlist` passes
   today because the test environment sets no `SIFTBOX_WAITLIST`, and
   would silently test the wrong thing the day a CI variable sets it.
