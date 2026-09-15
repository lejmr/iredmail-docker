# Development

Being written during the 2026 refresh; sections are filled as the pieces land.

## Run it

Against the official iRedMail image (`test/compose.yaml`'s default,
`iredmail/mariadb:stable`):

    bin/test.sh

Against this repo's own image (phase A, `image/`) - build it once, then
point the suite at the tag (`bin/test.sh` never builds it):

    docker buildx build --platform linux/amd64 -t iredmail-phase-a:dev -f image/Dockerfile image
    IMAGE=iredmail-phase-a:dev bin/test.sh

Either way: `bin/test.sh` brings up A, B and a DNS sidecar from
`test/compose.yaml` (`docker compose up -d`, no rebuild unless the target
`IMAGE` has a `build:` entry - this repo's own tag doesn't, by design, see
below), waits for A/B to report `healthy`, runs the acceptance suite, and
tears everything down (`compose down -v`) even on failure. To run the two
servers only (no suite), see `test/README.md`.

## Tests

`test/` holds the acceptance suite: one test per row of `ACCEPTANCE.md`,
named after the row (`test/test_acceptance.py`), written against public
interfaces only (see `CLAUDE.md`) - SMTP/IMAP/HTTPS/ActiveSync/CalDAV
sockets and the `admin` CLI run inside the container (`docker compose exec
mail-a admin ...`, the suite's only `exec`). `pytest` with plain
`smtplib`/`imaplib`/`requests`; `openssl s_client` where a raw TLS
handshake is clearer. The same 27 tests run against either image - see
`test/README.md` for the `IMAGE`/`MAIL_A_HOST`/etc. variables that select
which pair of servers, and "DNS sidecar" for how row 6's DKIM check and
A -> B routing go through a real DNS lookup rather than a shortcut.

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
  inspect -f '{{.Size}}'`) - well over the 800 MB phase-A ceiling in
  `ACCEPTANCE.md` row 15; recorded, not worked on further in this repo's
  final refresh (see `CLAUDE.md`).

## image/ (phase A)

iRedMail 1.8.8 (open source edition), unattended-installed on
`debian:13-slim` entirely inside `docker build` (`image/Dockerfile`). See
that file's comments for exactly which iRedMail installer variables are
set and why (systemd is faked out during the build - there is no init
system under `docker build` - and a temporary MariaDB instance is started
for the SQL schema import, same idea as the retired `mysql/Dockerfile`).

Build and run the two-server harness (own compose project + port offset,
never collides with anything else on the machine):

    docker buildx build --platform linux/amd64 -t iredmail-phase-a:dev -f image/Dockerfile image
    docker compose -p imagea -f compose.yaml up -d
    docker compose -p imagea ps                 # wait for both `healthy`
    docker compose -p imagea down -v             # tear down, including volumes

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

`CLAMAV=0` (default, per the 2026-09-15 decision) - iRedMail's installer
cannot skip installing ClamAV, so it ships in the image either way;
`CLAMAV=0` just stops both its supervisord programs and disables the
`ClamAV::Daemon` line in Amavis's content-filter config at every start.
Set `CLAMAV=1` to turn it back on.

## Verifying a change

Every change is proven from a fresh `compose up` on the integration commit,
never from a running instance somebody has been poking at. Anything touching
the web/ActiveSync surface is also exercised with a real client by the
maintainer (batch), after the machine rows are green.
