# Development

How this image is built, proven and released. The process behind it is the
maintainer's `drive-change` skill; `CLAUDE.md` maps it onto this repository.

## Layout

| Path | What |
|---|---|
| `image/` | the Dockerfile, `build/` (build-time helpers), `scripts/` (entrypoint, first start, per-boot config rendering, migrations, overrides, healthcheck, the `admin` CLI) |
| `compose.yaml` | two servers (`mail-a`, `mail-b`) on one network - the shape of a real deployment, also usable for manual testing |
| `test/` | the acceptance suite (`pytest`), `compose.yaml` for the suite (servers + a CoreDNS sidecar), `dns/` zone files, `admin-shims/` for running the suite against other images |
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
