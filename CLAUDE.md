# iredmail-docker - context for agents

Work here follows the maintainer's user-level **drive-change** skill. This
file supplies what the skill leaves to the project.

- **What we are building:** a minimal, fully tested, multi-domain mail server
  image that replaces iCloud for its maintainer (mail, calendar, contacts with
  push on the phone via ActiveSync; the same data on the laptop via
  IMAP + CalDAV + CardDAV). `ACCEPTANCE.md` is the specification.
- **Phases:** A = iRedMail (current release) on Debian 13 slim, so the test
  suite has a real target quickly. B = a hand-composed minimal stack
  (Postfix, Dovecot, Rspamd, Radicale, grommunio-sync) that passes the
  **same** suite. The suite never encodes which phase it is testing.
- **Tests are user stories through public interfaces only** (SMTP, IMAP,
  HTTPS, ActiveSync, CalDAV/CardDAV, the `admin` CLI). Never `docker exec`
  into internals, never read config, never grep logs for implementation
  details (the only log assertion is "no `error` at startup", row 1).
- **Fresh environment:** `docker compose -f test/compose.yaml up -d --build`
  starts two servers (A, B) on one network; `bin/test.sh` runs the suite
  against them and tears down. Details in `DEVELOPMENT.md`.
- **Decisions (2026-09-15):** Debian 13 slim base; Rspamd instead of
  Amavis+SpamAssassin+ClamAV where the phase allows (ClamAV optional);
  MariaDB only while SOGo needs it; `admin` CLI inside the image is the
  management contract; images on GHCR and Docker Hub, tagged by date, rebuilt
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
