# Contributing

The rules that shape this codebase are written down, and they apply to
every pull request, not only to the author's.

- Read `CLAUDE.md` and the short files in `.claude/rules/` before changing
  anything. Match the surrounding code first.
- Write the test first. Red, green, refactor.
- Run `bin/ci` before pushing: tests, RuboCop, Brakeman and bundler-audit.
- Style-only changes go in their own commit, apart from behaviour changes.
- Commit messages have an imperative subject and a prose body that says
  what changed and why.
- The pull request description leads with what the change does and what
  it costs. A change that adds an environment variable touches the README.
