#!/bin/bash
# Brings a fresh Claude Code on the web container to the point where bin/ci
# can run: system libraries, gems, and a test database.
set -euo pipefail

# A local checkout has bin/setup and a developer driving it. This only fixes
# what a throwaway remote container is missing.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# libvips backs image_processing, which ActiveStorage uses to analyse a blob.
# Without it the specs asserting stored image dimensions fail for a reason
# that has nothing to do with the code under test — and a red suite on a
# clean checkout invites a hunt for a bug that is not there. The index needs
# refreshing first: the image ships with stale package lists and the pinned
# versions 404.
if ! ldconfig -p | grep -q libvips; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq libvips42
fi

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
