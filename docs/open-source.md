# Making siftbox open source

An exploration, written against `d85d84b` (the head of `main` on 18 September
2026) before any of it is done. Nothing here has been carried out. The work
it proposes is cut into packages in `docs/open-source-plan.md`.

## Summary

The repository is close to publishable. One secret is committed in plain text
and has to be rotated before the visibility changes: the Honeybadger project
key in `config/honeybadger.yml`, present since the commit that added the gem.
Nothing else in the working tree or in any of the thirty commits of history
is a credential. The master key was never committed, the deploy secrets file
was never committed, and the test fixtures and the editor's corpus are
fabricated rather than copied from real newsletters.

Beyond that one key, the work divides into three parts. The first is
hygiene: rotate the key, take the production host's address and the Docker
Hub username out of the committed deploy config, add a licence. The second
is making the app usable by someone who is not its author: the landing page
collects waitlist signups for one particular product, the reader account and
two secrets come from an encrypted file only the author can open, and the
README is a runbook for one deployment rather than an introduction. The
third is presentation: a public README with a screenshot, the repository
settings, and a decision about how to present the fact that most commits
were written with Claude.

The proposal is three pull requests in that order, then the visibility
change, with a short list of things that only the repository owner can do in
the GitHub and Honeybadger dashboards. The cost is a permanent maintenance
obligation, a public origin address in history whatever is done now, and a
codebase whose deployment config no longer matches one machine. What it does
not fix: the app stays single-reader, stays tied to Postmark for inbound
mail, and the morning edition still costs money every day it runs.

## Two audiences and three secret stores

The word "user" covers two people who want different things from the
repository, and the app keeps secrets in three places that sound alike.

| Term | Meaning in this document |
|---|---|
| Self-hoster | Someone who clones the repository to run their own siftbox. They need it to boot without the author's keys. |
| Reviewer | Someone reading the repository to judge the author's work. They need the README to explain the app in a minute and the code to be worth the second minute. |
| Contributor | Someone opening a pull request. There may never be one, but the rules they would follow already exist in `CLAUDE.md` and `.claude/rules/`. |

| Store | Where | Who can read it |
|---|---|---|
| Rails credentials | `config/credentials.yml.enc`, committed, encrypted with `config/master.key`, which is not committed | Only holders of the master key. Today: the reader account, the Action Mailbox ingress password, the Postmark send token. |
| Kamal secrets | `.kamal/secrets-common`, gitignored, read at deploy time and passed into the container as environment variables | Only the deploy machine. Today: the registry password and the Anthropic key. |
| Plain config | `config/deploy.yml` and `config/honeybadger.yml`, committed | Everyone who can see the repository. Today: the production host address, the Docker Hub username, the Honeybadger key. |

The third row is the problem. The first row is an inconvenience for
self-hosters, discussed below.

## What was checked

Observations first. Each row is something that was looked at, with what was
found.

| Checked | Found |
|---|---|
| Every string in history matching a secret pattern | One real value: the Honeybadger key, `config/honeybadger.yml:4`, added in `a5b6556` on 7 August 2026 and unchanged since. Every other match (`KAMAL_REGISTRY_PASSWORD=...` and the like) is a placeholder in documentation. |
| Files ever committed with secret-like names | `config/credentials.yml.enc` only. No `master.key`, no `secrets-common`, no `.env`, no `.pem`. |
| Personal details in history | The production address `46.224.179.132`, six occurrences across the history of `config/deploy.yml` and `docs/deploying.md`. One `chris@siftbox.co`, used as an example in `docs/deploying.md`. The Docker Hub username `cjgilbert` in `config/deploy.yml`. |
| Remote branches | `main` and this one. Nothing else would become public. |
| Test fixtures | One 74-byte PNG. No `.eml` files, no real newsletter bodies. |
| The editor's corpus and the sample data | `lib/edition_corpus.rb` says in its header that every sender, company and figure is invented, and the senders it lists bear that out. `lib/tasks/sample_data.rake` uses real newsletter names as senders but fabricated bodies. |
| Gem sources | rubygems.org only. No private source. |
| Licence | None. No `LICENSE`, no `COPYING`, nothing in the README. |
| Fonts | Loaded from Google Fonts at request time (`app/views/layouts/application.html.erb:34`). Nothing vendored, so no font licence travels with the repository. Archivo and JetBrains Mono are both under the SIL Open Font License in any case. |
| Third-party text | `CLAUDE.md` says the rules were rephrased from thoughtbot's guides, which are CC-BY, and credits them. That attribution has to stay. |
| CI | `.github/workflows/ci.yml` runs Brakeman, importmap audit, RuboCop, bundler-audit and the suite on every pull request and on pushes to `main`. Dependabot is configured daily for gems and actions. |
| The suite at this commit | See the last section. |
| Commit authorship | Thirty commits. Twenty-six are authored by the owner, four by Claude, and most carry a `Co-Authored-By: Claude` trailer. |

## What has to change before the visibility changes

### The Honeybadger key must be rotated, not only removed

Removing the line from `config/honeybadger.yml` is not enough, because the
value stays in `a5b6556` and every commit after it. Once the repository is
public, anyone can read it from history. So the order is: generate a new
project key in the Honeybadger dashboard, put the new one somewhere not
committed, revoke the old one, and only then change the file.

Honeybadger reads `HONEYBADGER_API_KEY` from the environment when the YAML
file names no key. So the change to the repository is to delete the
`api_key` line, and the change to the deployment is to add the variable to
`.kamal/secrets-common` and to `env.secret` in `config/deploy.yml`, beside
`ANTHROPIC_API_KEY`, which already follows this pattern.

What the key permits, as far as the gem's own use of it shows: sending error
reports and Insights events into the project. It does not read anything.
The harm from a leak is therefore noise and cost in the Honeybadger account,
not access to the app. That was not verified against Honeybadger's
documentation.

Rewriting history to remove the value is not recommended. Rotation makes the
old value worthless, and a rewrite would change every commit hash after
`a5b6556`, which breaks the commit links in every merged pull request and
the commit references in `docs/` (for example `f9e976d` in
`docs/blogs-rss-reply.md`).

### The production host's address and the registry username should leave the committed config

`config/deploy.yml` names the host at lines 22 and 146 and the Docker Hub
username at lines 9 and 59, and `docs/deploying.md` repeats the address in
its DNS table. Publishing the origin address is a small risk today, and
`docs/deploying.md` already says scanners find it within minutes of a
DNS-only deploy. Two things make it worth moving anyway. The README says the
host is shared with the owner's other apps, so the address identifies more
than siftbox. And history is permanent: if the site ever goes behind
Cloudflare, the origin address will still be readable in the repository.

Kamal supports a per-destination file merged over `config/deploy.yml`, so
the values can move without changing how deploys work. The committed file
keeps everything generic (service name, volume, health check, the
`SIFTBOX_*` variable names with placeholder values) and a gitignored
`config/deploy.production.yml` carries the host, the registry username, the
proxy host and the real variable values. Deploys become
`bin/kamal deploy -d production`. The `.dockerignore` already excludes
`config/deploy*.yml`, so nothing changes in the image.

The cost: the runbook in `docs/deploying.md` loses its worked example and has
to describe the destination file instead, and there is one more file on the
deploy machine that a fresh clone does not have. The address that is already
in history stays there.

The alternative is to leave it. That is defensible on the grounds the README
already gives, and it is what many personal projects do. It is a decision
for the owner. This document recommends moving it because the shared host
is the owner's, not siftbox's.

### A licence has to be chosen

Without a licence file the repository is public but not open source: the
default is all rights reserved, and a self-hoster has no permission to run
it. Two choices fit the stated aims.

| Licence | What it does | When to choose it |
|---|---|---|
| MIT | Anyone may use, copy, modify and redistribute, including in closed products, as long as the notice stays. | The aim is reuse and a portfolio. Reviewers and self-hosters both recognise it and nobody has to read it. |
| AGPL-3.0 | The same, except that anyone who runs a modified version as a network service has to publish their modifications. | The aim includes stopping someone hosting a closed fork. |

MIT is recommended. The app is a single-reader tool people run for
themselves. There is no hosted version to protect, and AGPL would make some
reviewers assume a business intent that the landing page copy disclaims.

The file goes at the root as `LICENSE`, with the copyright line naming the
owner and the year. The README gets one line pointing at it.

### The encrypted credentials file is a decision, not a blocker

`config/credentials.yml.enc` is safe to publish in the sense that it cannot
be read without the master key. Two things follow from publishing it anyway.
If the master key ever leaks, every historical version of the file becomes
readable, including the ingress password rotated in `5c8c9fb`. And a
self-hoster who runs `bin/rails credentials:edit` on a fresh clone gets a
decryption error, because the file is there and their key is not. They have
to delete it first, and nothing tells them to.

The minimum is one line in the README: delete the file before creating your
own credentials. The better change is described in the next section.

## What should change so someone else can run it

### The landing page and waitlist belong to siftbox.co, not to the app

`/` serves a signed-out visitor a page that says "Join the waitlist" and,
under "Want an address?", that "Siftbox is a side project, built for one
person's reading habit. The waitlist tells me whether to make it work for
more" (`config/locales/en.yml`, `waitlist_signups.closing.body`). The "me"
is the owner. A self-hoster's instance would collect signups for a product
that does not exist and show the page to their own visitors.

The change is a switch. When the waitlist is off, `/` sends a signed-out
visitor to the sign-in page and the signup endpoint is not routed. When it is
on, everything works as today. An environment variable, read into
`config.x` in `config/application.rb` the way `SIFTBOX_INBOUND_ADDRESS` is,
with the default off. The owner's deployment sets it on.

It is a small change: `WaitlistSignupsController#new` gains a branch, the
route gains a constraint or the controller answers 404 on `create`, and each
gets a request spec. The cost is one more variable in the table of things
that fail quietly, and a landing page that no longer appears in a fresh
development environment unless asked for.

The alternative is to leave the landing page out of the open-source
repository entirely and keep it in a private branch. That splits the code
into two things to maintain and is not recommended.

### Secrets should come from the environment, so nobody needs the master key

Today a self-hoster has to create their own encrypted credentials with three
things in it (the reader account, the ingress password, the Postmark send
token) and keep a master key on every machine that deploys. The README
spends several paragraphs on why the ingress password lives in credentials
rather than in the `RAILS_INBOUND_EMAIL_PASSWORD` variable Action Mailbox
also reads, and on the merge order of two Kamal secrets files.

All of that goes away if the app reads those three values from the
environment, which is what it already does for the Anthropic key and what
Kamal's `env.secret` exists for.

| Value | Today | Proposed |
|---|---|---|
| Ingress password | `credentials.action_mailbox.ingress_password` | `RAILS_INBOUND_EMAIL_PASSWORD`, which Action Mailbox reads with no code change. The README's objection was to setting both; with the credential gone there is one. |
| Postmark send token | `credentials.postmark.smtp_token`, read in `config/environments/production.rb:78` | `POSTMARK_SMTP_TOKEN`. The README already documents this name, and the code diverged from it in `efce5ac`. |
| Reader account | `credentials.reader`, read in `db/seeds.rb` | `SIFTBOX_READER_EMAIL` and `SIFTBOX_READER_PASSWORD`, read in the same place with the same create-never-update rule. |
| `secret_key_base` | Rails derives it from the credentials file | `SECRET_KEY_BASE`, which Rails reads when there is no credentials file. |

Then `config/credentials.yml.enc` can be deleted and the master key is no
longer needed by anyone. `.kamal/secrets` shrinks to a list of variable names.

The cost is real. It is four files and a careful release: the running
deployment has to carry every value across in the same deploy as the code,
the way the `NEWSBOX_*` rename did, or password reset and inbound mail both
stop. The README's reasoning about credentials, which is some of its best
writing, gets replaced with a shorter table. And the seeds go back to
reading the environment, which the seeds file's own comment argues against
for a reason that still holds: a missing variable at first boot should log
and continue, not abort. That guard stays.

### The README is a runbook for one deployment and needs to become an introduction

The current README is accurate about what it covers and is written for the
person who already runs it. Three things about it will mislead a reviewer or
a self-hoster.

It is out of date in places. Line 6 says "Three screens" and describes the
feed and the reader, but the app now opens on the morning edition, has an
originals archive, a subscriptions page, a settings page and blog feeds. The
variable table at line 112 says `POSTMARK_SMTP_TOKEN` is an environment
variable, but `config/environments/production.rb:78` reads it from
credentials. The layout comment at `app/views/layouts/application.html.erb:19`
says opening a newsletter marks it read, which the README itself says was
retired.

It has no picture. A reviewer decides in the first screen whether to read
on, and the app's whole argument is visual: a newsletter stripped of its
sender's styling, an edition under a masthead. The `verify` skill in
`.claude/skills/` already describes taking a screenshot with Playwright
against sample data. `sample_data:load` creates newsletters but no edition,
so a screenshot of the edition page needs either a sample edition added to
that task or a real one copied from the owner's instance with the sources
checked for anything private.

It leads with operations. The proposal is a new README of roughly a hundred
lines: one paragraph on what it is, the screenshot, a short section on how
it works (mail arrives at one address, is sanitised at render, has its images
fetched and self-hosted, and is read by a model into a daily edition), five
commands to run it locally, one line per external service with what happens
without it, a pointer to `docs/deploying.md`, a pointer to `CLAUDE.md` and
the rules, and the licence. The existing README moves to
`docs/operating.md` with its stale lines fixed, because the material in it
(the variables that fail quietly, the egress rule, why sanitising happens at
render) is worth keeping and a self-hoster will need it on day two.

### The edition needs a paid key, and the app should say so on the page

`Edition::Draft` names `claude-opus-5` with a 32,000-token ceiling
(`app/models/edition/draft.rb:12` and `:27`), and `config/recurring.yml`
schedules a composition every morning in production. Without
`ANTHROPIC_API_KEY` the job raises a `KeyError` and the reader's home is the
editions archive, which says "No editions yet. The first one is written at
07:00". For a self-hoster without a key that sentence is never going to be
true.

Two options. The smaller is documentation: the README states that editions
need an Anthropic key, gives the owner's measured daily cost once there is
one (the PRD's figure of about $0.45 is arithmetic, and
`docs/briefing-followups.md` says so), and says the originals archive works
without it. The larger is a product change: with no key, the app treats
editions as off, `/` sends a signed-in reader to the originals archive, and
the masthead drops the Editions link. That is a design decision the PRD did
not make, and this document only names it.

Documentation is enough for the first release.

### Two short files that a public repository is expected to have

`SECURITY.md`, with an address for reporting and a sentence about what is
in scope. This app fetches URLs chosen by anyone who can send mail to the
inbound address, and the README explains at length how that is defended.
Someone who finds a hole in `Download::Destination` needs to know where to
send it other than a public issue.

`CONTRIBUTING.md`, of about ten lines: read `CLAUDE.md` and `.claude/rules/`,
run `bin/ci` before pushing, write the test first. The rules already exist.
This file tells a stranger they apply to them too.

## What to leave as it is

**The single reader.** The README's last paragraph already says what
multiple readers would take. A self-hoster is one reader. Adding accounts
to be open source would be building for a user who has not asked.

**The commit history and the Claude trailers.** Most commits say Claude
co-authored them. Rewriting that out would be dishonest, and a rewrite has
the cost described above. The choice is how to present it, which is a
README decision: a sentence saying the app was built with Claude Code and
that `CLAUDE.md` and `.claude/rules/` are how the author directs it. A
reviewer in 2026 will read that as a skill being demonstrated, and the
rules files are unusually specific evidence of it.

**The design and planning documents.** `docs/briefing-prd.md`,
`docs/blogs-rss.md`, `docs/blogs-rss-plan.md` and `docs/siftbox-redesign.md`
are the strongest portfolio material in the repository, because they show
decisions being made with measurements and the trade-offs written down. Two
of them reference things that are not in the repository:
`docs/siftbox-redesign.md` opens by citing `design_handoff_siftbox/README.md`,
and `docs/blogs-rss-reply.md` is addressed to a branch that no longer exists
and cites a `docs/silencing.md` that was never merged. A one-line note at
the top of each, saying what the missing thing was, is enough. Deleting the
reply is also reasonable, since it was a message rather than a record.

**SQLite, Kamal, Postmark.** All three are choices a self-hoster can live
with, and swapping any of them is a project of its own. Postmark is the one
a self-hoster is most likely to ask about, because Action Mailbox supports
other ingresses and the app's own code does not care which. The answer for
now is a line in the README saying the ingress is set in
`config/environments/production.rb:7` and that nothing else is Postmark
specific except password-reset mail.

**`CLAUDE.md` and `.claude/`.** They become public. Nothing in them is
private: the hook installs packages, the skill uses `reader@example.com`
and a placeholder password, and the rules are the point.

## Presenting it as portfolio work

What a reviewer sees, in order: the repository description and topics in
the GitHub listing, the README's first screen, the CI badge, the file tree,
then whichever of `app/models/` or `spec/` they open. Each of those is a
small task.

- **Repository settings**, done by the owner in the GitHub interface: a
  one-line description, the website field set to siftbox.co, topics
  (`rails`, `hotwire`, `action-mailbox`, `newsletters`, `rss`, `sqlite`,
  `kamal`), and a social preview image, which can be the same screenshot.
- **Secret scanning and push protection**, both switched on in the
  repository's security settings once it is public. They are free for
  public repositories and would have caught the Honeybadger key at push
  time if the pattern is one GitHub recognises, which was not verified.
- **Branch protection on `main`** requiring the CI workflow to pass. Today
  nothing enforces it.
- **A CI badge** in the README, which is one line once the workflow is
  public.
- **Dependabot's cadence.** It is set to daily with a limit of ten open
  pull requests for each of two ecosystems. On a public repository that is
  a visible stream of bot activity in the pull request list. Weekly, with
  minor and patch updates grouped, keeps the list readable.
- **Issues.** Enabling them invites reports. Leaving them off is a
  legitimate choice for a personal project, and `SECURITY.md` gives the one
  route that matters an address.

## What this costs and what it leaves unfixed

Going public creates an obligation that does not end. Dependabot pull
requests keep arriving whether or not anyone reads them, a security report
has to be answered within days, and a self-hoster's question about Postmark
or the egress rule is a question about the owner's time. The README should
say what level of support to expect, in one sentence, so nobody is misled.

The deployment config and the repository stop describing one machine. Today
`config/deploy.yml` is the truth about production. After the change, the
truth is split between a committed template and a file that exists only on
the deploy machine, and a mistake in the merge (a value in both, say) fails
in the way `.kamal/secrets` already warns about.

The origin address stays in history. Moving it out of the working tree
stops it appearing in the file a reader opens; it does not remove it from
`git log -p`. If that matters, the only remedy is a rewrite, with the cost
described above, or a new address.

The switch for the landing page is one more variable and one more branch to
test, in an app that has been careful to have few of either.

Left unfixed by all of this: the app serves one reader and will not serve
two without the three steps at the end of the README; inbound mail needs a
Postmark account, which is free at siftbox's volume but is still an
account; the morning edition costs money every day it runs and produces
nothing without a key; and a failed image fetch is still not retried, as
`docs/deploying.md` records under "Still open".

## Proposed order of work

Three pull requests, each a deploy on its own, then the visibility change.

1. **Hygiene.** Rotate the Honeybadger key in the dashboard first. Then, in
   one pull request: delete the `api_key` line and add
   `HONEYBADGER_API_KEY` to `env.secret`; move the host, registry username,
   proxy host and variable values into a gitignored
   `config/deploy.production.yml` and put placeholders in `config/deploy.yml`;
   replace the address in `docs/deploying.md` with a placeholder; add
   `LICENSE`. Deploy, and confirm errors still reach Honeybadger.
2. **Self-hosting.** In one pull request, with the tests first: the
   waitlist switch; the four values moved from credentials to the
   environment and `config/credentials.yml.enc` deleted; the new README,
   with the old one moved to `docs/operating.md` and its stale lines fixed;
   `SECURITY.md` and `CONTRIBUTING.md`; the two notes on the docs that cite
   missing files. Deploy, carrying every value across in the same release,
   and run the smoke test in `docs/deploying.md` step 8 in full, because
   inbound mail and password reset both change how they are configured.
3. **Presentation.** The screenshot, the CI badge, the Dependabot cadence,
   and the sentence about how the app was built.
4. **Owner-only steps**, in the GitHub interface: description, website,
   topics, social preview; then change the visibility; then turn on secret
   scanning, push protection and branch protection, which are only offered
   once the repository is public.

Step 1 is the only one that has to happen before the visibility changes.
Steps 2 and 3 could follow in public, at the cost of the first reviewers
seeing the runbook README and a fork that cannot boot.

## The suite at this commit

Run in this session against `d85d84b`, with the session's own
`bin/rails db:test:prepare` and no master key.

| Check | Result |
|---|---|
| `bin/rspec` | 1134 examples, 0 failures, in 12 seconds |
| `bin/rubocop` | 205 files, no offences |
| `bin/brakeman` | no warnings |

`bundle-audit` was not run here. It needs the advisory database fetched
over the network, and CI runs it on every push in any case.
