---
name: verify
description: Build/launch siftbox and drive it through the browser to verify a change at its real surface (authenticated Rails views behind session auth).
---

# Verifying siftbox at runtime

This app is a server-rendered Rails app behind session auth (one reader
account). The surface is HTTP/browser, not the test suite — `bin/rspec`
proves CI passes, not that a page actually works.

## Launch

```bash
bin/rails db:prepare                 # idempotent; safe to re-run
bin/rails runner '
  User.find_or_create_by!(email_address: "reader@example.com") { |u| u.password = "password123456" }
'
bin/rails server -p 3101 -d          # pick a port unlikely to collide; -d backgrounds it
```

Kill it when done: `kill $(cat tmp/pids/server.pid)`.

## Sign in and drive a page

No API session shortcut exists — go through the real form. Two ways:

**curl (fast, good for checking response bodies/headers):**
```bash
curl -s -c cookies.txt -b cookies.txt http://localhost:3101/session/new -o signin.html
csrf=$(grep -o 'name="authenticity_token" value="[^"]*"' signin.html | sed 's/.*value="\(.*\)"/\1/')
curl -s -c cookies.txt -b cookies.txt -X POST http://localhost:3101/session \
  --data-urlencode "authenticity_token=$csrf" \
  --data-urlencode "email_address=reader@example.com" \
  --data-urlencode "password=password123456" -D - -o /dev/null | head -3
curl -s -c cookies.txt -b cookies.txt http://localhost:3101/<path>
```

**Playwright (for visual/screenshot evidence):** `playwright-core` isn't
vendored in the repo; install it ad hoc in the scratchpad dir
(`npm install playwright-core --no-save`) and launch with
`executablePath: "/opt/pw-browsers/chromium"` (pre-installed; don't run
`playwright install`). Fill the sign-in form directly rather than
transplanting cookies — cookie-jar-to-Playwright cookie transplants are
fiddly (domain/HttpOnly parsing) and just re-driving the form is more
reliable:

```js
await page.goto("http://localhost:3101/session/new");
await page.fill('input[name="email_address"]', "reader@example.com");
await page.fill('input[name="password"]', "password123456");
await page.click('input[type="submit"], button[type="submit"]');
await page.waitForLoadState("networkidle");
await page.goto("http://localhost:3101/<path>");
await page.screenshot({ path: "...", fullPage: true });
```

Check both breakpoints the design system defines: below 720px (mobile nav
layout) and above.

## Useful adjacent probes

- Signed-out request to any authenticated path → expect `302` to
  `/session/new` (the `Authentication` concern's default).
- A `resource :x, only: :show` route should 404 on POST/PATCH and on
  `/x/1` — confirms no wider surface leaked through.
- If a page displays a `config.x.*` value, override its `ENV` var and
  restart the server to confirm the page reads config live rather than a
  hardcoded string.
- CSS `text-transform: uppercase` only changes rendering — confirm the
  underlying response body/DOM text is unchanged (matters for anything a
  reader is meant to copy, like an email address).

## Gotchas

- `bin/rails runner` fails with `no such table` if `db:prepare` hasn't
  run yet in this environment — run it first.
- The dev SQLite file and any runner-created rows are local scratch;
  `git status` after a verify session to confirm nothing app-side got
  dirtied (there shouldn't be a tracked dev DB).
