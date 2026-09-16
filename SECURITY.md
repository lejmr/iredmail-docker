# Security

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability
reporting on this repository (Security → Report a vulnerability) or write to
the maintainer's address in `plugin`-less form: milos.kozak@lejmr.com. You
will get an acknowledgement, a fix on a private branch, and credit in the
release notes if you want it.

## What this image is responsible for

The mail software inside is iRedMail's - Postfix, Dovecot, MariaDB, Amavis,
SpamAssassin, ClamAV, iRedAPD, iRedAdmin, SOGo, nginx - and their
vulnerabilities are theirs to fix; this image's job is to ship current
versions of them (the base image and packages are rebuilt weekly) and to not
add holes of its own: how secrets are generated and stored, which services
are reachable from the network, which privileges the container needs, what
happens on restart, upgrade, backup and restore.

## Hardening in the 2026 refresh

Each item was reproduced on the previous image or found while proving the
acceptance rows, fixed, and is covered by a test in `test/` or by an
attack step in `_test/validation-plan.md`-style checks. Described by class.

### High

- **Configuration lost on container recreation.** Secrets were substituted
  into `/etc` and `/opt` once, on first start; a `docker compose down`/`up`
  brought every service back with placeholder passwords and no TLS
  certificate. Configuration is now rendered from the persisted secrets on
  every start.
- **Backups contained no mail.** `admin backup` archived the mail store as a
  bare symlink. Fixed; a backup is proven by restoring it onto an empty
  server and reading the mail over IMAP.
- **Silent data loss on a missing volume mount.** A forgotten `-v` produced
  an anonymous volume that vanished on the next recreate. The container now
  refuses to start unless every data path is a mount (issue #84).

### Medium

- **Plaintext IMAP (143) reachable from the network** alongside the
  intended ports. Everything but 25, 465, 587, 993, 443 (+80) now listens on
  loopback only, verified by a port scan from a sibling container.
- **Technical database accounts with full rights** (issue #57). Every
  component's account is now limited to its own database with the minimum
  statements; only `root@localhost` is unrestricted.
- **Quota not enforced for authenticated senders**: the quota policy check
  sat behind `permit_sasl_authenticated`. Moved to end-of-data; an
  over-quota mailbox now answers `552 5.2.2`.
- **One DKIM key for every container built from the image** (issue #17,
  regressed twice in the old image). Keys are generated per container at
  first start and per domain; two servers from one image are proven to have
  different keys.
- **Mailbox password reset on every restart** (issue #47). `POSTMASTER_PASSWORD`
  is applied only when the account is created.

### Low

- No `--privileged`: the container runs with `cap_drop: ALL` plus the seven
  capabilities the services actually need (documented in `compose.yaml`).
- iRedMail's installer tarball is pinned by version and SHA-256, not by a
  mutable git tag.
- Secrets live in `/data/secrets` with mode 0600 and never in
  world-readable configuration; `POSTMASTER_PASSWORD_FILE` avoids putting
  the password into the container environment.
- Development and test files are not part of the image.

## What is not covered

- Fail2ban and the host firewall: the container has no `NET_ADMIN`; rate
  limiting and banning belong to the host or the reverse proxy.
- TLS certificates: the image generates a self-signed certificate with the
  configured hostname; production must mount real ones (`/data/certs`).
- The web applications (iRedAdmin, SOGo) run as shipped by iRedMail; their
  own security posture is upstream's.
- Image size (≈2 GB) is recorded, not optimised - see the README's note on
  Stalwart for what to run instead if that matters to you.
