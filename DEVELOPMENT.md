# Development

How this image is built, proven and released. The process behind it is the
maintainer's `drive-change` skill; `CLAUDE.md` maps it onto this repository.

## Layout

| Path | What |
|---|---|
| `image/` | the Dockerfile, `build/` (build-time helpers), `scripts/` (entrypoint, first start, per-boot config rendering, migrations, overrides, healthcheck, the `admin` CLI) |
| `compose.yaml` | two servers (`mail-a`, `mail-b`) on one network - the shape of a real deployment, also usable for manual testing |
| `test/` | the acceptance suite (`pytest`), `compose.yaml` for the suite (`mail-a`/`mail-b` + a CoreDNS sidecar, and `mail-c` - `profiles: [restore]`, row 14's backup-restore target, started only when that row needs it), `dns/` zone files, `admin-shims/` for running the suite against other images |
| `bin/test.sh` | fresh `compose up` → wait healthy → suite → `down -v`; exit code is pytest's |
| `bin/merge-stages.sh` | lands a validated integration branch as topical squash PRs whose combined tree is byte-identical to what was validated |
| `ACCEPTANCE.md` | the specification: twenty rows in the words of someone running the server; the required subset for this repository is listed at the bottom |

## Build

    docker build --platform linux/amd64 -t iredmail-phase-a:dev image/

The image is amd64 only (SOGo has no arm64 build). On an Apple Silicon
Mac the build works under Rosetta - Colima: `colima start --vm-type vz
--vz-rosetta --cpu 6 --memory 12`; Docker Desktop: enable "Use Rosetta for
x86_64/amd64 emulation". Under plain QEMU emulation Python 3.13 segfaults
inside `dpkg` postinst scripts and the build cannot finish - that is the
emulator, not the image. The iRedMail install layer takes ~8 minutes under
Rosetta and is cached; script-only changes rebuild in about a minute.

The build runs iRedMail's unattended installer against a temporary MariaDB
(`AUTO_USE_EXISTING_CONFIG_FILE`, `AUTO_INSTALL_WITHOUT_CONFIRM`; the
tarball is pinned by version and SHA-256), dumps the resulting databases,
replaces every generated secret with a placeholder, and converts the
systemd units iRedMail wrote into supervisord programs. At first start the
container generates its own secrets, DKIM key and self-signed certificate,
restores the dumps, and creates the first domain; on **every** start it
renders the placeholders from `/data/secrets`, applies `overrides/`, and
runs pending schema migrations.

## Run it

    docker compose up -d            # two servers, a.example and b.example
    docker compose exec mail-a admin domain list

Both servers refuse to start unless all five data paths are mounts
(`/data/mysql`, `/data/vmail`, `/data/certs`, `/data/secrets`,
`/data/overrides`). `PEER_DOMAINS="b.example=mail-b"` routes mail between
the two without DNS; the test suite does not use it - it runs a real DNS.

Environment: `MAIL_DOMAIN`, `POSTMASTER_PASSWORD` or
`POSTMASTER_PASSWORD_FILE`, `TZ`, `CLAMAV=0|1`, `SOGO_WORKERS`,
`PEER_DOMAINS`.

## Tests

    bin/test.sh                                   # everything, ~12 min on the Mac above
    IMAGE=iredmail/mariadb:stable bin/test.sh     # the same suite against the official image (admin shim)
    pytest test/test_acceptance.py -k row06       # one row against servers you started yourself

One test per row of `ACCEPTANCE.md`, black-box: SMTP, IMAP, HTTPS,
ActiveSync, CalDAV/CardDAV and `docker compose exec <server> admin …` -
the `admin` command is the management contract, and the only thing the
suite executes inside a container. No config reads, no `doveadm`, no log
grepping beyond row 1's "no `error` at startup". The suite creates every
domain, user and message it needs through those interfaces and removes
them again; nothing is planted.

The two servers resolve each other through a CoreDNS sidecar authoritative
for `a.example` and `b.example` (A, MX, and the DKIM TXT records, which
the suite reads with `admin dkim` after the servers are healthy and loads
into the zone) - so row 6's `dkim=pass` is real, not simulated.

`test/junit.xml` is written on every run; the release workflow turns it
into the per-row table in the release notes.

Row 21 (import from the old `lejmr/iredmail:mysql-1.3*` image) uses a
fixture checked into `test/fixtures/legacy-1.3/` (`dump.sql`, `vmail.tar`) -
a real `mysqldump`/`tar` taken off a real old container, not hand-built
bytes. The suite never touches Docker Hub for it. To regenerate it (e.g.
after changing what `import-legacy` expects), see
`test/fixtures/legacy-1.3/MAKE.md` and run
`test/fixtures/legacy-1.3/make-fixture.sh`.

## Details

### This host

An arm64 Mac running Colima (`vmType: vz`, Rosetta for amd64 emulation,
not QEMU - see "Build" below), 6 CPUs / 12 GiB / 100 GiB disk allocated to
the VM. Runtime numbers measured here, for calibration:

- `image/Dockerfile` build (`--platform linux/amd64`, cold): ~8 minutes
  under Rosetta - most of it iRedMail's own unattended installer. Not
  needed for every test run; build once, reuse the tag (`IMAGE=
  iredmail-phase-a:dev`).
- `bin/test.sh` against the built image, warm (image already pulled/built,
  no cold-boot penalty beyond first-start.sh's own DKIM keygen etc.): the
  27-test suite completes in under 10 minutes end to end (compose up,
  health wait, pytest, teardown).
- Image size: `iredmail-phase-a:dev` is currently ~1.9 GB (`docker image
  inspect -f '{{.Size}}'`) - within `ACCEPTANCE.md` row 15's 2000 MB
  ceiling (revised 2026-09-16 to the honest number for iRedMail + SOGo +
  ClamAV on Debian, which is ~1.9 GB; the earlier 800 MB figure was never
  achievable without dropping ClamAV or SOGo, decided out of scope).


### Build: a known local limitation, not an image bug

Earlier on this same kind of host (arm64 Mac, Colima running amd64 under
**QEMU** user-mode emulation), the build reached the unattended `bash
iRedMail.sh` step and failed partway through apt's dependency install:
every `python3-*` package's postinst byte-compiles with `py3compile`,
which shells out to `python3.13 -c 'import sys;
print(sys.implementation.cache_tag)'` - and that subprocess **segfaulted**
(exit status -11) under QEMU. That was a QEMU/Python 3.13 interaction on
the build host, not a bug in `image/Dockerfile` or the installer variables
(everything up to that apt run - config generation, the temporary MariaDB
bootstrap - completed correctly both times it was tried).

**Resolved on this host** by switching Colima to Rosetta instead of QEMU
(`vmType: vz`, Rosetta enabled for amd64 emulation) - the same build then
completes in full, in ~8 minutes (see "This host" above). If a local build
still segfaults the way described, the host is very likely still on QEMU;
switch it (`colima start --vm-type vz --vz-rosetta`, or the equivalent in
`~/.colima/default/colima.yaml`) before assuming an image bug. Failing
that, or on non-Apple-Silicon hosts without Rosetta, build in CI instead:
`.github/workflows/build.yml` runs on GitHub's amd64 runners, builds the
image, reports its size, runs the acceptance suite against a fresh
`compose up` when `bin/test.sh` exists, and pushes to GHCR on `master`.


### `admin` CLI

`/usr/local/bin/admin` inside the container (bash, no extra deps):

    admin domain add <domain>                 # prints the MX + DKIM TXT to publish
    admin domain rm <domain>
    admin domain list
    admin user add <addr> --password <p> --quota <1G|512M|...>
    admin user rm <addr>
    admin user list [domain]
    admin user quota <addr> <q>
    admin user passwd <addr> <password>
    admin dkim <domain>
    admin backup > backup.tar                 # SQL dumps + vmail + dkim + certs
    admin restore < backup.tar                # into an EMPTY server only
    admin import-legacy <dump.sql> <vmail.tar> [--force]
                                               # one-time move from lejmr/iredmail:mysql-1.3*

Every domain gets its own 2048-bit DKIM key (`/var/lib/dkim/<domain>.pem`);
`admin domain add`/`rm` fully regenerate Amavis's
`/etc/amavis/conf.d/60-dkim-domains` from the `domain` SQL table on every
call, so there is never a shared/wildcard signing key (#50, #92).


### Volumes and the overrides/ mechanism

`/data/mysql`, `/data/vmail`, `/data/certs`, `/data/overrides` - all four
must be real mounts or the container refuses to start (`mountpoint -q`,
row 13 / #84). Real certs dropped into `/data/certs/cert.pem` +
`/data/certs/key.pem` before first start win over the self-signed one
first-start.sh generates.

`/data/overrides/postfix/main.cf.d/*.cf`: plain `key = value` lines,
applied with `postconf -e` on every start (survives an upgrade because it
lives on the volume, not in a layer).
`/data/overrides/dovecot/*.conf`: Dovecot config snippets - `dovecot.conf`
already carries `!include_try /data/overrides/dovecot/*.conf` (added once
at build time).


### Two servers without public DNS

`PEER_DOMAINS="b.example=mail-b"` (comma-separated for more peers) makes
`image/scripts/peer-domains.sh` write a Postfix transport table so mail to
that domain goes straight to the named host on the same docker network,
ahead of iRedMail's own SQL-backed transport maps - see `compose.yaml` at
the repo root for the two-server (A/B) wiring this drives.


### ClamAV

`CLAMAV=1` (default, per the 2026-09-16 decision - restores the old
`lejmr/iredmail` image's behaviour) - iRedMail's installer cannot skip
installing ClamAV, so it ships in the image either way; `CLAMAV=0` is an
explicit opt-out that stops both its supervisord programs (`clamav-daemon`,
`clamav-freshclam`) and disables the `ClamAV::Daemon` line in Amavis's
content-filter config at every start, for hosts tight on RAM (roughly 1 GB
less resident). The image's own `HEALTHCHECK` (and the acceptance suite's
compose healthcheck) only reports healthy once `clamdscan --ping` succeeds
when ClamAV is on - clamd does not bind its control socket until its
signature database has finished loading, so this doubles as "the database
is loaded", not just "the process is running". `image/Dockerfile` also sets
`ConcurrentDatabaseReload no` in `clamd.conf` so a signature update does not
briefly double clamd's resident memory.

### Spam and viruses (row 9)

Amavis + SpamAssassin (+ ClamAV) as iRedMail ships them, with two overrides
from iRedMail's own defaults, both in `image/Dockerfile`:

- `$final_spam_destiny = D_PASS` (iRedMail default: `D_DISCARD`) - spam is
  tagged (`X-Spam-Flag: YES`, added once the SpamAssassin score is at or
  above `$sa_tag2_level_deflt`) and still delivered, instead of silently
  dropped. Dovecot's global "before" sieve script
  (`image/scripts/sieve/dovecot.sieve`, baked into the image at
  `/usr/local/lib/iredmail/sieve/` rather than the `/data/vmail` volume -
  it must survive a `down`/`up` with no volume restore step, and every
  upgrade with no migration step) files anything so tagged into the Junk
  folder (`lda_mailbox_autocreate = yes` creates it on first use).
- `$final_virus_destiny = D_REJECT` (iRedMail default: `D_DISCARD`), **and**
  submission/smtps in `/etc/postfix/master.cf` use `smtpd_proxy_filter`
  (Amavis's SMTP-based before-queue filtering) instead of `content_filter`.
  Both are needed for a live SMTP `5xx` on the sender's own connection: with
  only the destiny change, Postfix's default AFTER-queue `content_filter`
  already answers the client's DATA command with `250` and queues the
  message before Amavis ever sees it, so a later reject at re-injection
  just generates a DSN into the sender's own mailbox instead - confirmed
  empirically (`mail.log`: `Blocked INFECTED ... {RejectedInternal,
  Quarantined}` with no exception on the still-open sending session).
  `smtpd_proxy_filter` streams the message to Amavis synchronously, in the
  same client session, so a reject becomes smtpd's own response - port 25
  (inbound from other MTAs, `content_filter` still, main.cf's global
  default) is deliberately left alone: rejecting anonymous inbound mail
  this way risks bouncing to a forged sender, which Amavis's own docs warn
  against.


## Verifying a change

A change is proven from a fresh `bin/test.sh` on the integration commit,
never on an instance that has been poked at. Anything touching the web or
ActiveSync surface is also exercised with a real client by the maintainer
(a batch of at most five steps with a "Good =" each), after the machine
rows are green. New behaviour = a new row first, then the test, then the
code; a test is mutation-checked (break the behaviour, watch it fail).

## Releasing

**Actions → Release → Run workflow** (blank version = today). The workflow
refuses if the date was already released or `CHANGELOG.md` has no
`## [YYYY-MM-DD]` section; then it builds on GitHub's amd64 runners, runs
the suite from a fresh compose up, requires the rows marked required in
`ACCEPTANCE.md` to pass, tags the commit, pushes the tested image to
`ghcr.io/lejmr/iredmail-docker` and `lejmr/iredmail` as `<date>` and
`latest`, and publishes a GitHub release whose notes are the changelog
section plus the literal per-row result. Docker Hub needs the repository
secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`; GHCR works with the
built-in token.

CI (`ci.yml`) runs static checks, the build, Trivy (recorded) and the
suite on every pull request and push to master, and **weekly** - a base
image security update or a vanished upstream repository shows up as a red
weekly run, not as a user's issue.

Landing: topical PRs from snapshot trees with `bin/merge-stages.sh` (see
its header); squash-only; the source must contain current `master`.

## Coming back after a long time

- GitHub disables scheduled workflows after 60 days without activity;
  push anything to re-enable the weekly run before trusting its silence.
- Check https://docs.iredmail.org/iredmail.releases.html and bump
  `IREDMAIL_VERSION` + `IREDMAIL_SHA256` in `image/Dockerfile`; migrations
  between versions are documented per release upstream and belong in
  `image/scripts/migrate.sh`.
- `debian:13-slim` will be superseded; the Dockerfile's base tag and the
  SOGo apt repository line are the two things that go stale.
- If none of that is worth your evening: the README already tells users
  to move to Stalwart.
