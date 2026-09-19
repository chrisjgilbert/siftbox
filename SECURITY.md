# Security

## Reporting

Email **[SECURITY CONTACT ADDRESS — not yet set]** rather than opening a
public issue. Say what you found, how to reproduce it, and what it reaches.
You will get a reply within **[REPLY WINDOW — not yet set] days** saying
whether it is confirmed and what happens next.

## What is in scope

This app fetches URLs it did not choose. Anyone who can send mail to the
inbound address decides which images it downloads, and a subscribed blog's
feed decides which pages it reads and where their redirects lead. It then
renders HTML written by those same strangers.

So the reports that matter are:

- Any request that reaches a private, link-local or otherwise non-public
  address through `Download::Destination`, which is the whole of the
  application-layer defence against server-side request forgery.
- Any script that runs on a rendered page, or markup that survives the
  sanitiser in a form it should not.
- Anything that lets a signed-out visitor read a newsletter, a post or an
  edition, or lets anyone but the reader change one.

The host-level egress rule in `docs/deploying.md` is a deploy step, not
code; a report that it is missing from a particular deployment belongs
with whoever runs that deployment.
