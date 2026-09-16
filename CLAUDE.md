# iredmail-docker - context for agents

Work here follows the maintainer's user-level **drive-change** skill. This
file supplies what the skill leaves to the project.

- **What we are building:** a minimal, fully tested, multi-domain mail server
  image that replaces iCloud for its maintainer (mail, calendar, contacts with
  push on the phone via ActiveSync; the same data on the laptop via
  IMAP + CalDAV + CardDAV). `ACCEPTANCE.md` is the specification.
- **Scope (decided 2026-09-15, after finding Stalwart):** this repository
  gets ONE final refresh so that existing users have a buildable, tested,
  released image - iRedMail (current release) on Debian 13 slim - and the
  same maintenance shape as lejmr/dokuwiki-plugin-drawio (dev env, acceptance
  suite, CI incl. weekly rebuild, release button, SECURITY.md, CHANGELOG.md,
  DEVELOPMENT.md). No feature work beyond what the acceptance rows need to
  pass - and every row must pass: CI is red on any failing or skipped row
  (decided 2026-09-16 after a 'recorded rows' gate proved confusing). The README states plainly that the maintainer recommends
  **Stalwart** (https://stalw.art) for new deployments - that is the only
  place Stalwart appears in this repository; nothing here targets it. The
  black-box suite would carry over to any other server, which is why it
  never encodes what it is testing.
- **Tests are user stories through public interfaces only** (SMTP, IMAP,
  HTTPS, ActiveSync, CalDAV/CardDAV, the `admin` CLI). Never `docker exec`
  into internals, never read config, never grep logs for implementation
  details (the only log assertion is "no `error` at startup", row 1).
- **Fresh environment:** `docker compose -f test/compose.yaml up -d --build`
  starts two servers (A, B) on one network; `bin/test.sh` runs the suite
  against them and tears down. Details in `DEVELOPMENT.md`.
- **Decisions (2026-09-15):** Debian 13 slim base; Amavis+SpamAssassin+ClamAV as iRedMail ships them, ClamAV on by default
  (`CLAMAV=0` opts out); spam is tagged and filed to Junk, never discarded;
  MariaDB only while SOGo needs it; `admin` CLI inside the image is the
  management contract for the tests, and a web admin UI (phase A: iRedAdmin;
  phase B: Postfixadmin or a minimal page - whichever passes row 20) is
  required for the maintainer; images on GHCR and Docker Hub, tagged by date, rebuilt
  weekly for security updates; arm64 not before phase B; old issues closed
  after the first release with one factual sentence each, feature requests
  mapped to acceptance rows.
- **Security:** findings and policy in `SECURITY.md` (to be written with the
  first fixes: #57 technical accounts, #47 password reset on restart,
  #17 shared DKIM key); no exploit recipes in public text.
- **Landing / release:** snapshot-tree squash PRs (`bin/merge-stages.sh`
  pattern from lejmr/dokuwiki-plugin-drawio); release from a GitHub Actions
  button only; changelog section required.
- **Maintainer:** Miloš Kozák; reads Czech, repository is English; decides
  up front, tests only what needs a real phone/client, answers `n good / m ko`.
