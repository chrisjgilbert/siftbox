# Ruby

## Size and shape

- Methods of one to five lines. A class past ~100 lines is probably doing more than one thing.
- Composition over inheritance. Classes over modules for behaviour shared between models.
- Avoid optional parameters, long parameter lists, and feature envy. Each usually means the
  method belongs somewhere else.
- Tell, don't ask: call a method on the object rather than reading its state and deciding on
  its behalf.
- Don't rescue and discard. Exceptions are for exceptional cases, not control flow.
- Don't write code for functionality that doesn't exist yet.
- No monkey-patching, no global variables.

## Naming

- Spell words out. No abbreviations.
- Don't put the type in the name: `users` not `user_array`, `Report` not `ReportModule`.
- Name classes after the domain concept, not the pattern used to build them: `Guest` over
  `NullUser`, `CachedRequest` over `RequestDecorator`.
- Block parameter is the singular of the collection: `users.each { |user| greet(user) }`.
- Predicate methods end in `?`. Avoid `!` names; pick a name that says what the method does.
- Background jobs end in `Job`.

## Style

- `private` for scope. `protected` only for comparison methods (`==`, `<`, `>`).
- Class methods above instance methods. `def self.method`, never `class << self`.
- Parentheses on `def` when there are arguments.
- Read through the reader method, not the instance variable. Memoisation ivars take a leading
  underscore: `@_total ||= ...` behind a `total` method.
- Prefix unused variables and block parameters with `_`.
- `detect`, `select`, `map`, `reduce` — not `find`, `find_all`, `collect`, `inject`.
- `&:method_name` for single-method blocks.
- No ternaries. Use a multi-line `if` so both branches are visible.
- One assignment per line. Trailing `if`/`unless` only on short lines.
- Double quotes by default. Heredoc for multi-line strings.
- No comments that only label a section (`# Validations`). A class needing section labels is
  too big.
- Two-space indent, no tabs. Break lines after 80 characters. No trailing whitespace.

## Gemfile

- Exact version for Rails. Pessimistic (`~>`) for gems that follow semver, such as rspec and
  factory_bot. Unpinned for gems that are safe to bump often.
- Ruby version pinned in the version-manager file and stated in the `Gemfile`.
- `ENV.fetch("KEY")`, so a missing variable fails at boot. `ENV["KEY"]` returns nil and fails
  somewhere else later.
