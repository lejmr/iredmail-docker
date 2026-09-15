# Development

Being written during the 2026 refresh; sections are filled as the pieces land.

## Run it

    docker compose -f test/compose.yaml up -d --build   # servers A and B
    bin/test.sh                                         # the acceptance suite

## Tests

`test/` holds the acceptance suite: one test per row of `ACCEPTANCE.md`,
named after the row, written against public interfaces only (see
`CLAUDE.md`). `pytest` with plain `smtplib`/`imaplib`/`requests`; `swaks`
and `openssl s_client` where a raw conversation is clearer. The suite takes
`MAIL_A`/`MAIL_B` host:port settings so it can run against any two servers -
this image, the official `iredmail/mariadb` image, or the phase-B stack.

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
