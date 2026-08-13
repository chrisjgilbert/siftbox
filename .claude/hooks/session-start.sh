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

# Test database only. db:prepare would also run the seeds, which read the
# reader's account out of encrypted credentials — unreadable here, since a
# remote container has no master key.
bin/rails db:test:prepare
