# Project: siftbox

Receives newsletter emails at one dedicated address via Action Mailbox and
Postmark, and presents them as a clean reading feed for a single reader.
A public landing page captures waitlist signups.

The visual system is documented in `docs/siftbox-redesign.md`: two typefaces,
where Archivo is never uppercase and JetBrains Mono always is; two rule
weights and nothing between them; no radius and no shadow anywhere. Spacing is
deliberately not tokenised — the design uses exact values per element.

## Commands

```bash
bin/dev                                   # dev server and worker
bin/rspec                                 # full suite
bin/rspec spec/models                     # one directory
bin/rspec spec/models/order_spec.rb:72    # one example
bin/rubocop                               # lint
bin/rubocop -a                            # autocorrect
bin/rails db:migrate
bin/rails routes
bundle audit                              # gem vulnerabilities
bin/ci                                    # tests, linters, security scanners
```

## Rules

Short constraints in `.claude/rules/`:

- `rules/ruby.md` — language style, naming, method and class size
- `rules/models.md` — domain objects in `app/models`, no service objects, callbacks
- `rules/controllers.md` — HTTP only, RESTful routes, strong params
- `rules/views.md` — no logic in views, presenters, Turbo
- `rules/database.md` — migrations, indexes, queries, column naming
- `rules/testing.md` — **write the test first**, no `let` or `before`
- `rules/security.md` — authorisation, injection, output safety
- `rules/review.md` — what to check on a diff, and which RuboCop cops not to silence

## Applying the rules

- Match the surrounding code first. If a file already breaks a rule, follow the file.
- Don't restyle code you weren't asked to change. Style-only changes go in their own commit.
- Breaking a rule is fine with a reason. Put the reason in the diff or the PR description.
- "Never" has no exceptions. "Avoid" needs a reason. "X over Y" means X unless Y is justified.

## Not adopted from the source guides

- Spring binstubs. Spring isn't part of current Rails defaults.
- `db/development_structure.sql`.
- `Delayed::Job` matchers. Use what this app's queue adapter provides.
- Heroku deployment steps.

Source: [thoughtbot/guides](https://github.com/thoughtbot/guides) — `rails/ai-rules`,
`rails`, `ruby`, `testing-rspec`, `general`, `object-oriented-design`. CC-BY, rephrased.
