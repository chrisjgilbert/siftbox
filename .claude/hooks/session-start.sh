#!/bin/bash
# Brings a fresh Claude Code on the web container to the point where bin/ci
# can run: gems, a PATH the binstubs' executables are on, and a test database.
# No system library to install — nothing this app bundles needs one.
set -euo pipefail

# A local checkout has bin/setup and a developer driving it. This only fixes
# what a throwaway remote container is missing.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

bundle check >/dev/null 2>&1 || bundle install

# Gems install their executables into Ruby's own bindir, and this image does
# not put that directory on PATH. The project's binstubs still work, so
# bin/rspec and bin/rubocop pass and only the last line of bin/ci dies —
# "bundler: command not found: bundle-audit", for a gem that is installed and
# listed in the bundle. Exporting the directory is what makes bin/ci
# runnable end to end.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$(ruby -e 'require "rubygems"; print Gem.bindir'):\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Test database only. db:prepare would also run the seeds, which read the
# reader's account out of SIFTBOX_READER_EMAIL and SIFTBOX_READER_PASSWORD —
# neither of which a remote container sets, so seeding here would create
# nothing and say so.
bin/rails db:test:prepare
