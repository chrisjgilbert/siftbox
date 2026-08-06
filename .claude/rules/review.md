# Reviewing a diff

On top of the other rules, check for:

- Migrations that drop data or can't be reversed. Say whether a backup is needed before the
  staging and production deploys.
- SQL built from user input.
- New columns or queries with no supporting index.
- New scheduled tasks. These need a deploy step; they don't install themselves.
- Dependency bumps with no reason in the commit message. Link the changelog entry.
- Anything left over from a removed feature: unused columns, dead partials, orphaned specs.

## RuboCop cops that need judgement

Autocorrect can't decide these. Don't add inline `# rubocop:disable` or `# rubocop:todo` to
make them go away — if a cop doesn't fit this codebase, say so in the final response and leave
it to the user.

- `Rails/OutputSafety` — never silence it. `html_safe` and `raw` are XSS holes. If a specific
  use is safe, explain why and let the user decide.
- `ThreadSafety/*` — never silence it. These catch real concurrency bugs. Describe what the cop
  caught, list the options (`Current`/`RequestStore`, instance state, a frozen constant, a
  mutex, or accepting it because the app runs single-threaded), then wait for direction.
- `Lint/Debugger` — never silence it. Remove the `binding.irb` or `debugger` line.
- `Rails/SkipsModelValidations` — `update_columns`, `update_all`, and `update_counters` skip
  callbacks on purpose for counter caches, audit fields, and bulk writes. Rewriting to `update`
  changes behaviour. Report it and explain, don't rewrite.
- `Rails/HasManyOrHasOneDependent` — usually a real bug, but some associations are meant to
  tolerate orphans. Report it rather than picking a `dependent:` value.
- `RSpec/MultipleExpectations`, `RSpec/NestedGroups` — restructuring often makes the spec worse.
  If it reads better as it stands, say so. Readability wins.
- `RSpec/AnyInstance` — usually a real problem, occasionally the only option in legacy code.
