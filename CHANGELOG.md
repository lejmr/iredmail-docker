# Changelog

Written for people running the image. The technical detail is in the pull
requests linked from each release on GitHub.

## [1.8.8]

The last feature release of this image. **For new deployments the
maintainer recommends [Stalwart](https://stalw.art) instead** - see the
README. This release exists so that people who already run this image get a
buildable, tested, current one.

### Changed

- Base image is `debian:13-slim` (was CentOS 7, end-of-life since 2024 and
  no longer buildable); iRedMail is 1.8.8 (was 1.3.1 on `master`, 1.6.1 in
  a side directory). Image published on GHCR and Docker Hub tagged with the iRedMail
  version (`1.8.8`, `latest`) and rebuilt weekly for security updates.
- The container runs without `--privileged`; Fail2ban is gone (host's job);
  ClamAV is **on by default** (`CLAMAV=0` is an explicit opt-out, saving
  about 1 GB RAM) - restores the old `lejmr/iredmail` image's behaviour.
  The container only reports healthy once ClamAV's database has finished
  loading, when it is on.
- Spam is tagged (`X-Spam-Flag: YES`) and filed to the Junk folder, never
  silently discarded; a virus gets a live SMTP `5xx` on the sender's own
  connection, never silently dropped (previously both were silently
  discarded with iRedMail's own defaults).
- Data lives in five named volumes (`/data/mysql`, `/data/vmail`,
  `/data/certs`, `/data/secrets`, `/data/overrides`); the container refuses
  to start if one is not mounted.
- Management is the `admin` command (domains, users, quotas, DKIM records,
  backup, restore, `import-legacy`) plus iRedAdmin.
- `admin import-legacy <dump.sql> <vmail.tar>` moves a `lejmr/iredmail:mysql-1.3*`
  server (the old CentOS 7 image) onto this one in one command: domains,
  users, aliases, quotas and mail all carry over, old passwords work
  unchanged - see the README's "Upgrade" section (row 21).
- Configuration overrides that survive upgrades: `overrides/postfix/main.cf.d/*.cf`
  and `overrides/dovecot/*.conf`.
- Schema migrations run automatically on start (`versions` table).

### Fixed

- Multiple domains on one server, each with its own DKIM key (#92, #50).
- `POSTMASTER_PASSWORD` no longer resets the mailbox password on every
  restart (#47).
- A missing volume mount is refused instead of silently losing data (#84).
- Technical database accounts limited to their own databases (#57).
- Every container gets its own DKIM keys (#17).
- Relay attempts without authentication get a hard `554`, not a temporary
  defer.
- Quotas are enforced for authenticated senders (`552 5.2.2` when over).
- Backups contain the mail; `backup`/`restore` exit codes are correct.
- Only 25, 465, 587, 993, 443 (+80) are reachable from the network.
- SpamAssassin's Bayes database and other state persist across restarts (#86).
- Every acceptance row is required in CI, and a skipped row is a failure -
  nmap and Trivy (rows 16, 15) now run from their own containers so neither
  the row nor its result ever depends on what is installed on the runner.

### Known limitations (not planned)

- Image size ≈ 2 GB.
- amd64 only (SOGo has no arm64 build).
- No OAuth2, no LDAP, no Kubernetes manifests.

## Older

`mysql-1.3.1` (2020) and the unreleased `Update to 1.6.1` directory (2022)
were CentOS 7 / Rocky 8 based; see git history.
